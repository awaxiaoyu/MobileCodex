import Foundation
import SwiftUI

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

  private let transport: NativeBridgeTransport
  private var backendId: String?
  private var generation: Int?
  private var streamId: String?
  private var sequence = 0

  override init() {
    transport = NativeBridgeTransport()
    super.init()
    transport.onStatusChange = { [weak self] in self?.status = $0 }
    transport.onMessage = { [weak self] in self?.handleEvent($0) }
    transport.onDisconnect = { [weak self] in self?.desktopReady = false }
    transport.onCredentialsRevoked = { [weak self] in self?.clearSessionState() }
    status = transport.status
    if transport.hasCredentials {
      Task { await connect() }
    }
  }

  var hasCredentials: Bool { transport.hasCredentials }

  func setNotice(_ value: String) { notice = value }

  func pair(from raw: String) async {
    do {
      try await transport.pair(from: raw)
      await connect()
    } catch {
      notice = error.localizedDescription
    }
  }

  func forget() {
    transport.forget()
    clearSessionState()
  }

  private func clearSessionState() {
    backendId = nil
    generation = nil
    desktopReady = false
    currentThread = nil
    currentTurnId = nil
    running = false
    approval = nil
    messages = []
    artifacts = []
    diff = ""
  }

  func connect() async {
    await transport.connect()
    if transport.isConnected { await load() }
  }

  private func rpc(_ method: String, _ payload: [String: Any], kind: String = "request", id: String? = nil,
                   backend: String? = nil, backendGeneration: Int? = nil) async throws -> [String: Any] {
    try await transport.rpc(method, payload, kind: kind, id: id,
                            backend: backend ?? backendId,
                            backendGeneration: backendGeneration ?? generation)
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
      diff = ""
      artifacts = []
      await snapshot()
    } catch { notice = error.localizedDescription }
  }

  func createThread() async {
    do {
      let response = try await rpc("bridge.thread.create", ["projectId": selectedProjectId])
      guard let thread = thread(from: nativeDictionary(nativeDictionary(response["payload"])?["thread"])) else { throw NativeBridgeError.invalidResponse }
      currentThread = thread
      messages = []
      currentTurnId = nil
      running = false
      streamId = nil
      sequence = 0
      approval = nil
      diff = ""
      artifacts = []
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
    try await transport.download(artifact, backendId: backendId, generation: generation, threadId: currentThread?.id)
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

}
