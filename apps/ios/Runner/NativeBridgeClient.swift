import Foundation
import Security
import SwiftUI
import UIKit
import CommonCrypto

@MainActor
final class NativeBridgeClient: NSObject, ObservableObject {
  @Published private(set) var status = "未连接"
  @Published private(set) var desktopReady = false
  @Published private(set) var projects: [NativeProject] = []
  @Published private(set) var threads: [NativeThread] = []
  @Published private(set) var models: [NativeModel] = []
  @Published private(set) var messages: [NativeMessage] = []
  @Published private(set) var artifacts: [NativeArtifact] = []
  @Published private(set) var diff = ""
  @Published private(set) var running = false
  @Published private(set) var notice = ""
  @Published private(set) var currentThread: NativeThread?
  @Published private(set) var currentTurnId: String?
  @Published var approval: NativeApproval?
  @Published var selectedProjectId = "workspace"
  @Published var selectedModel: String?
  @Published var selectedEffort: String?
  @Published var mode = "default"

  // Match the Flutter client's default Apple Keychain envelope so an existing
  // pairing survives the platform migration.
  private let keychainKey = "bridge"
  private let keychainService = "flutter_secure_storage_service"
  private var credentials: NativeCredentials?
  private var session: URLSession?
  private var socket: URLSessionWebSocketTask?
  private var pending: [String: PendingRPC] = [:]
  private var requestCounter = 0
  private var backendId: String?
  private var generation: Int?
  private var streamId: String?
  private var sequence = 0
  private var reconnectTask: Task<Void, Never>?
  private var retryAttempt = 0

  override init() {
    super.init()
    credentials = readCredentials()
    if credentials != nil {
      Task { await connect() }
    }
  }

  deinit {
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    session?.invalidateAndCancel()
  }

  var hasCredentials: Bool { credentials != nil }

  func setNotice(_ value: String) { notice = value }

  func pair(from raw: String) async {
    do {
      guard let data = raw.data(using: .utf8),
            let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let urlText = value["url"] as? String,
            let url = URL(string: urlText),
            url.scheme == "wss",
            url.path == "/ws",
            let fingerprint = value["fingerprint"] as? String,
            let id = value["id"] as? String,
            let secret = value["secret"] as? String else {
        throw NativeBridgeError.invalidPairing
      }
      try validateFingerprint(fingerprint)
      let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "iPhone"
        : UIDevice.current.name
      let delegate = PinningDelegate(fingerprint: fingerprint)
      let pairingSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
      var pairURL = url.deletingLastPathComponent().appendingPathComponent("pair")
      pairURL.scheme = "https"
      var request = URLRequest(url: pairURL)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "secret": secret, "name": deviceName])
      let (data, response) = try await pairingSession.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = result["token"] as? String,
            let deviceId = result["deviceId"] as? String else {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"].flatMap(nativeDictionary).flatMap { $0["message"] }.flatMap(nativeString)
        throw NativeBridgeError.rpc(code: "pair.failed", message: message ?? "配对失败", requestId: "pair")
      }
      let saved = NativeCredentials(url: urlText, fingerprint: fingerprint, token: token, deviceId: deviceId, deviceName: deviceName)
      saveCredentials(saved)
      credentials = saved
      pairingSession.invalidateAndCancel()
      await connect()
    } catch {
      notice = error.localizedDescription
    }
  }

  func forget() {
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    session?.invalidateAndCancel()
    socket = nil
    session = nil
    credentials = nil
    deleteCredentials()
    backendId = nil
    generation = nil
    desktopReady = false
    currentThread = nil
    messages = []
    artifacts = []
    diff = ""
    status = "未连接"
  }

  func connect() async {
    guard let credentials else { return }
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    session?.invalidateAndCancel()
    status = "连接中"
    let delegate = PinningDelegate(fingerprint: credentials.fingerprint)
    let nextSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    session = nextSession
    var request = URLRequest(url: URL(string: credentials.url)!)
    request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
    request.setValue("\(credentials.deviceName)", forHTTPHeaderField: "x-mobile-device-name")
    let task = nextSession.webSocketTask(with: request)
    socket = task
    task.resume()
    await waitForSocket(task)
  }

  private func waitForSocket(_ task: URLSessionWebSocketTask) async {
    for _ in 0..<50 {
      if task.state == .running {
        status = "已连接"
        retryAttempt = 0
        startReceiveLoop(task)
        await load()
        return
      }
      if task.state == .completed || task.state == .canceling { break }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    status = "连接失败"
    scheduleReconnect()
  }

  private func startReceiveLoop(_ task: URLSessionWebSocketTask) {
    task.receive { [weak self] result in
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch result {
        case let .success(message):
          if case let .string(text) = message { self.handle(text) }
          self.startReceiveLoop(task)
        case .failure:
          guard self.socket === task else { return }
          if task.closeCode == .policyViolation {
            self.forget()
            self.status = "设备已撤销，请重新配对"
            return
          }
          self.status = "连接中断"
          self.desktopReady = false
          self.failPending(with: NativeBridgeError.disconnected)
          self.scheduleReconnect()
        }
      }
    }
  }

  private func scheduleReconnect() {
    guard credentials != nil else { return }
    reconnectTask?.cancel()
    let delay = [1, 2, 4, 8, 16, 30][min(retryAttempt, 5)]
    retryAttempt += 1
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
      guard !Task.isCancelled else { return }
      if let self { await self.connect() }
    }
  }

  private func failPending(with error: Error) {
    let waiters = pending.values
    pending.removeAll()
    for waiter in waiters {
      waiter.timeoutTask?.cancel()
      waiter.continuation.resume(throwing: error)
    }
  }

  func rpc(_ method: String, _ payload: [String: Any], kind: String = "request", id: String? = nil, backend: String? = nil, backendGeneration: Int? = nil) async throws -> [String: Any] {
    guard let socket, socket.state == .running else { throw NativeBridgeError.disconnected }
    requestCounter += 1
    let requestId = id ?? "ios-\(Date().timeIntervalSince1970)-\(requestCounter)"
    var envelope: [String: Any] = ["v": 1, "kind": kind, "id": requestId, "method": method, "payload": payload]
    if let backend = backend ?? self.backendId { envelope["backendId"] = backend }
    if let generation = backendGeneration ?? self.generation { envelope["backendGeneration"] = generation }
    let data = try JSONSerialization.data(withJSONObject: envelope)
    let text = String(decoding: data, as: UTF8.self)
    return try await withCheckedThrowingContinuation { continuation in
      pending[requestId] = PendingRPC(continuation: continuation, timeoutTask: nil)
      pending[requestId]?.timeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 35_000_000_000)
        guard !Task.isCancelled, let waiter = self?.pending.removeValue(forKey: requestId) else { return }
        waiter.continuation.resume(throwing: NativeBridgeError.rpc(code: "backend.result_unknown", message: "操作超时，请先查询结果", requestId: requestId))
      }
      socket.send(.string(text)) { [weak self] error in
        guard let error else { return }
        Task { @MainActor [weak self] in
          guard let waiter = self?.pending.removeValue(forKey: requestId) else { return }
          waiter.timeoutTask?.cancel()
          waiter.continuation.resume(throwing: error)
        }
      }
    }
  }

  private func handle(_ text: String) {
    guard let data = text.data(using: .utf8), let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    if let id = message["id"] as? String, let waiter = pending.removeValue(forKey: id) {
      waiter.timeoutTask?.cancel()
      if message["kind"] as? String == "error", let payload = nativeDictionary(message["payload"]) {
        waiter.continuation.resume(throwing: NativeBridgeError.rpc(code: nativeString(payload["code"]) ?? "rpc.error", message: nativeString(payload["message"]) ?? "请求失败", requestId: id))
      } else {
        waiter.continuation.resume(returning: message)
      }
      return
    }
    handleEvent(message)
  }

  private func handleEvent(_ event: [String: Any]) {
    if event["method"] as? String == "event.connection.ready" {
      Task { await load() }
      return
    }
    if event["method"] as? String == "event.backend.status" {
      desktopReady = nativeString(nativeDictionary(event["payload"])?["status"]) == "connected"
      if desktopReady { Task { await load() } }
      return
    }
    guard event["backendId"] as? String == backendId else { return }
    if let eventSequence = event["seq"] as? Int {
      if let streamId, event["streamId"] as? String != streamId || (eventSequence > sequence + 1 && streamId != nil) {
        Task { await snapshot() }
        return
      }
      if eventSequence <= sequence { return }
      streamId = event["streamId"] as? String
      sequence = eventSequence
    }
    let payload = nativeDictionary(event["payload"]) ?? [:]
    let method = event["method"] as? String
    if method == "event.serverRequest.resolved" || method == "event.serverRequest.claimed" {
      if nativeString(payload["requestId"]) == approval?.id { approval = nil }
      return
    }
    if method == "event.task.status" {
      if let eventTurnId = nativeString(payload["turnId"]) { currentTurnId = eventTurnId }
      if let status = nativeString(payload["status"]) {
        running = ["inProgress", "started"].contains(status)
        if ["completed", "interrupted", "failed"].contains(status) {
          running = false
          Task { await snapshot() }
        }
      }
      return
    }
    if method == "event.item.delta", nativeString(event["threadId"]) == currentThread?.id {
      let itemId = nativeString(payload["itemId"]) ?? UUID().uuidString
      let turnId = nativeString(payload["turnId"]) ?? "turn"
      let role: NativeMessage.Role = switch nativeString(payload["type"]) {
      case "reasoning": .reasoning
      case "plan": .plan
      default: .assistant
      }
      if let index = messages.firstIndex(where: { $0.id == itemId }) {
        messages[index].text += nativeString(payload["delta"]) ?? ""
      } else {
        messages.append(NativeMessage(id: itemId, turnId: turnId, role: role, text: nativeString(payload["delta"]) ?? ""))
      }
    }
    if method == "event.diff.updated", nativeString(event["threadId"]) == currentThread?.id {
      diff = nativeString(payload["diff"]) ?? ""
    }
    if event["kind"] as? String == "server.request", let id = event["id"] as? String {
      approval = NativeApproval(id: id, method: method ?? "", payload: payload, backendId: event["backendId"] as? String, generation: event["backendGeneration"] as? Int, threadId: event["threadId"] as? String, turnId: event["turnId"] as? String)
    }
  }

  func load() async {
    do {
      let result = try await rpc("bridge.backends.list", [:])
      let backends = nativeArray(nativeDictionary(result["payload"])?["backends"])
      guard let shared = backends.first(where: { nativeString($0["kind"]) == "desktop-shared" && nativeString($0["status"]) == "connected" }) else {
        desktopReady = false
        notice = "电脑未连接"
        return
      }
      let nextBackendId = nativeString(shared["id"])
      let nextGeneration = shared["generation"] as? Int
      if nextBackendId != backendId || nextGeneration != generation {
        currentThread = nil
        messages = []
        streamId = nil
        sequence = 0
        approval = nil
      }
      desktopReady = true
      backendId = nextBackendId
      generation = nextGeneration
      let projectsResponse = try await rpc("bridge.project.list", [:])
      projects = nativeArray(nativeDictionary(projectsResponse["payload"])?["projects"]).compactMap { value in
        guard let id = nativeString(value["projectId"] ?? value["id"]) else { return nil }
        return NativeProject(id: id, label: nativeString(value["label"] ?? value["name"]) ?? id, branch: nativeString(value["branch"] ?? value["branchName"]))
      }
      let chatsResponse = try await rpc("bridge.thread.list", ["limit": 50])
      threads = nativeArray(nativeDictionary(chatsResponse["payload"])?["threads"]).compactMap(thread(from:))
      let modelsResponse = try await rpc("bridge.model.list", ["limit": 100])
      models = nativeArray(nativeDictionary(modelsResponse["payload"])?["data"]).compactMap { value in
        guard value["hidden"] as? Bool != true, let id = nativeString(value["model"] ?? value["id"]) else { return nil }
        let efforts = (value["supportedReasoningEfforts"] as? [Any] ?? []).compactMap { nativeDictionary($0).flatMap { nativeString($0["reasoningEffort"]) } ?? nativeString($0) }
        return NativeModel(id: id, label: nativeString(value["displayName"] ?? value["name"]) ?? id, efforts: efforts)
      }
      if selectedModel == nil { selectedModel = models.first?.id }
      if !projects.contains(where: { $0.id == selectedProjectId }) { selectedProjectId = projects.first?.id ?? selectedProjectId }
      notice = ""
    } catch {
      notice = error.localizedDescription
    }
  }

  func select(_ thread: NativeThread) async {
    do {
      if !thread.title.isEmpty { _ = try await rpc("bridge.thread.resume", ["threadId": thread.id]) }
      currentThread = thread
      currentTurnId = nil
      messages = []
      streamId = nil
      sequence = 0
      await snapshot()
    } catch { notice = error.localizedDescription }
  }

  func createThread() async {
    do {
      let response = try await rpc("bridge.thread.create", ["projectId": selectedProjectId])
      guard let thread = thread(from: nativeDictionary(nativeDictionary(response["payload"])?["thread"])) else { throw NativeBridgeError.invalidResponse }
      currentThread = thread
      messages = []
      mode = "plan"
    } catch { notice = error.localizedDescription }
  }

  func send(_ text: String) async {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    do {
      if currentThread == nil { await createThread() }
      guard let thread = currentThread else { return }
      let method = running ? "bridge.turn.steer" : "bridge.turn.start"
      var payload: [String: Any] = ["threadId": thread.id, "input": [["type": "text", "text": value]]]
      if !running {
        if let selectedModel {
          payload["model"] = selectedModel
          var settings: [String: Any] = ["model": selectedModel]
          if let selectedEffort { settings["reasoning_effort"] = selectedEffort }
          payload["collaborationMode"] = ["mode": mode, "settings": settings]
        }
        if let selectedEffort { payload["effort"] = selectedEffort }
      }
      _ = try await rpc(method, payload)
      running = true
      threads.removeAll { $0.id == thread.id }
      threads.insert(NativeThread(id: thread.id, title: currentThread?.title ?? String(value.prefix(80)), projectId: thread.projectId, preview: value, pinned: thread.pinned), at: 0)
      if currentThread?.title.isEmpty != false { currentThread?.title = String(value.prefix(80)) }
    } catch { notice = error.localizedDescription }
  }

  func interrupt() async {
    guard let thread = currentThread else { return }
    guard let currentTurnId else { notice = "当前任务还没有 turn ID"; return }
    var payload: [String: Any] = ["threadId": thread.id]
    payload["turnId"] = currentTurnId
    do { _ = try await rpc("bridge.turn.interrupt", payload) } catch { notice = error.localizedDescription }
  }

  func respond(to approval: NativeApproval, payload: [String: Any]) async {
    do {
      var envelopeBackend = backendId
      var envelopeGeneration = generation
      if let approvalBackend = approval.backendId { envelopeBackend = approvalBackend }
      if let approvalGeneration = approval.generation { envelopeGeneration = approvalGeneration }
      _ = try await rpc(approval.method, payload, kind: "server.response", id: approval.id, backend: envelopeBackend, backendGeneration: envelopeGeneration)
      self.approval = nil
    } catch { notice = error.localizedDescription }
  }

  private func snapshot() async {
    guard let currentThread else { return }
    do {
      let response = try await rpc("bridge.snapshot.get", ["threadId": currentThread.id])
      let payload = nativeDictionary(response["payload"]) ?? [:]
      let thread = nativeDictionary(payload["thread"]) ?? [:]
      messages = flattenMessages(thread["turns"])
      streamId = nativeString(response["streamId"])
      sequence = response["seq"] as? Int ?? sequence
      if let latestTurn = nativeArray(thread["turns"]).last {
        currentTurnId = nativeString(latestTurn["id"])
        running = nativeString(latestTurn["status"]) == "inProgress"
      } else {
        currentTurnId = nil
        running = false
      }
      if let requests = (payload["approvals"] as? [Any])?.compactMap({ $0 as? [String: Any] }).first {
        approval = NativeApproval(id: nativeString(requests["id"]) ?? "", method: nativeString(requests["method"]) ?? "", payload: nativeDictionary(requests["payload"]) ?? [:], backendId: response["backendId"] as? String, generation: response["backendGeneration"] as? Int, threadId: nativeString(requests["threadId"]), turnId: nativeString(requests["turnId"]))
      }
      do {
        let artifactResponse = try await rpc("bridge.artifact.list", ["threadId": currentThread.id])
        artifacts = nativeArray(nativeDictionary(artifactResponse["payload"])?["artifacts"]).compactMap { value in
          guard let id = nativeString(value["id"]), let name = nativeString(value["name"]) else { return nil }
          return NativeArtifact(id: id, name: name, size: value["size"] as? Int ?? 0, contentType: nativeString(value["contentType"]) ?? "application/octet-stream")
        }
      } catch {
        artifacts = []
      }
    } catch { notice = error.localizedDescription }
  }

  func download(_ artifact: NativeArtifact) async throws -> URL {
    guard let credentials, let base = URL(string: credentials.url), let session else { throw NativeBridgeError.disconnected }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    components?.scheme = "https"
    components?.path = "/artifacts/\(artifact.id)"
    components?.queryItems = [
      URLQueryItem(name: "backendId", value: backendId ?? ""),
      URLQueryItem(name: "generation", value: String(generation ?? 0)),
      URLQueryItem(name: "threadId", value: currentThread?.id ?? "")
    ]
    guard let url = components?.url else { throw NativeBridgeError.invalidResponse }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NativeBridgeError.invalidResponse }
    let safeName = artifact.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(artifact.id)-\(safeName)")
    try data.write(to: file, options: .atomic)
    return file
  }

  private func thread(from value: [String: Any]?) -> NativeThread? {
    guard let value, let id = nativeString(value["id"]) else { return nil }
    return NativeThread(id: id, title: nativeString(value["title"] ?? value["name"]) ?? "未命名聊天", projectId: nativeString(value["projectId"] ?? value["project_id"]), preview: nativeString(value["preview"] ?? value["lastMessage"]), pinned: (value["pinned"] as? Bool == true) || (value["isPinned"] as? Bool == true))
  }

  private func flattenMessages(_ turns: Any?) -> [NativeMessage] {
    nativeArray(turns).flatMap { turn in
      nativeArray(turn["items"]).compactMap { item in
        guard let id = nativeString(item["id"]), let text = nativeString(item["text"] ?? item["content"]) else { return nil }
        let type = nativeString(item["type"]) ?? "agentMessage"
        let role: NativeMessage.Role = type == "userMessage" ? .user : type == "reasoning" ? .reasoning : type == "plan" ? .plan : .assistant
        return NativeMessage(id: id, turnId: nativeString(turn["id"]) ?? "turn", role: role, text: text)
      }
    }
  }

  private func validateFingerprint(_ value: String) throws {
    let normalized = value.replacingOccurrences(of: ":", with: "").lowercased()
    guard normalized.count == 64, normalized.allSatisfy({ $0.isHexDigit }) else { throw NativeBridgeError.invalidFingerprint }
  }

  private func saveCredentials(_ value: NativeCredentials) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainKey]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
  }

  private func readCredentials() -> NativeCredentials? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainKey, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(NativeCredentials.self, from: data)
  }

  private func deleteCredentials() {
    SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainKey] as CFDictionary)
  }
}

private final class PinningDelegate: NSObject, URLSessionDelegate {
  private let expected: String

  init(fingerprint: String) {
    expected = fingerprint.replacingOccurrences(of: ":", with: "").lowercased()
  }

  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          let certificate = SecTrustGetCertificateAtIndex(trust, 0),
          let data = SecCertificateCopyData(certificate) as Data? else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    let digest = SHA256.hex(data)
    guard digest == expected else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}

private enum SHA256 {
  static func hex(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: 32)
    data.withUnsafeBytes { buffer in
      var context = CC_SHA256_CTX()
      CC_SHA256_Init(&context)
      _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
      CC_SHA256_Final(&digest, &context)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
