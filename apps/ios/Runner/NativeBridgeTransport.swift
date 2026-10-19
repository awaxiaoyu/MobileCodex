import Foundation
import Security
import UIKit
import CommonCrypto

@MainActor
final class NativeBridgeTransport: NSObject {
  var onStatusChange: ((String) -> Void)?
  var onMessage: (([String: Any]) -> Void)?
  var onDisconnect: (() -> Void)?
  var onCredentialsRevoked: (() -> Void)?

  private(set) var status = "未连接"
  private let keychainKey = "bridge"
  private let keychainService = "flutter_secure_storage_service"
  private var credentials: NativeCredentials?
  private var session: URLSession?
  private var socket: URLSessionWebSocketTask?
  private var pending: [String: PendingRPC] = [:]
  private var requestCounter = 0
  private var reconnectTask: Task<Void, Never>?
  private var retryAttempt = 0

  override init() {
    super.init()
    credentials = readCredentials()
  }

  deinit {
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    session?.invalidateAndCancel()
  }

  var hasCredentials: Bool { credentials != nil }
  var isConnected: Bool { socket?.state == .running }

  func pair(from raw: String) async throws {
    guard let rawData = raw.data(using: .utf8),
          let value = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
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
    let pairingSession = URLSession(configuration: .ephemeral, delegate: PinningDelegate(fingerprint: fingerprint), delegateQueue: nil)
    let pairPath = url.deletingLastPathComponent().appendingPathComponent("pair")
    guard var pairComponents = URLComponents(url: pairPath, resolvingAgainstBaseURL: false) else {
      throw NativeBridgeError.invalidPairing
    }
    pairComponents.scheme = "https"
    guard let pairURL = pairComponents.url else { throw NativeBridgeError.invalidPairing }
    var request = URLRequest(url: pairURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "secret": secret, "name": deviceName])
    let (responseData, response) = try await pairingSession.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          let result = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
          let token = result["token"] as? String,
          let deviceId = result["deviceId"] as? String else {
      let failure = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
      let message = nativeString(nativeDictionary(failure?["error"])?["message"])
      pairingSession.invalidateAndCancel()
      throw NativeBridgeError.rpc(code: "pair.failed", message: message ?? "配对失败", requestId: "pair")
    }
    let saved = NativeCredentials(url: urlText, fingerprint: fingerprint, token: token, deviceId: deviceId, deviceName: deviceName)
    saveCredentials(saved)
    credentials = saved
    pairingSession.invalidateAndCancel()
  }

  func forget() {
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    session?.invalidateAndCancel()
    socket = nil
    session = nil
    credentials = nil
    deleteCredentials()
    failPending(with: NativeBridgeError.disconnected)
    setStatus("未连接")
  }

  func connect() async {
    guard let credentials else { return }
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    session?.invalidateAndCancel()
    setStatus("连接中")
    let nextSession = URLSession(configuration: .default, delegate: PinningDelegate(fingerprint: credentials.fingerprint), delegateQueue: nil)
    session = nextSession
    var request = URLRequest(url: URL(string: credentials.url)!)
    request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
    request.setValue(credentials.deviceName, forHTTPHeaderField: "x-mobile-device-name")
    let task = nextSession.webSocketTask(with: request)
    socket = task
    task.resume()
    await waitForSocket(task)
  }

  func rpc(_ method: String, _ payload: [String: Any], kind: String = "request", id: String? = nil,
           backend: String? = nil, backendGeneration: Int? = nil) async throws -> [String: Any] {
    guard let socket, socket.state == .running else { throw NativeBridgeError.disconnected }
    requestCounter += 1
    let requestId = id ?? "ios-\(Date().timeIntervalSince1970)-\(requestCounter)"
    var envelope: [String: Any] = ["v": 1, "kind": kind, "id": requestId, "method": method, "payload": payload]
    if let backend { envelope["backendId"] = backend }
    if let backendGeneration { envelope["backendGeneration"] = backendGeneration }
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

  func download(_ artifact: NativeArtifact, backendId: String?, generation: Int?, threadId: String?) async throws -> URL {
    guard let credentials, let base = URL(string: credentials.url), let session else { throw NativeBridgeError.disconnected }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    components?.scheme = "https"
    components?.path = "/artifacts/\(artifact.id)"
    components?.queryItems = [
      URLQueryItem(name: "backendId", value: backendId ?? ""),
      URLQueryItem(name: "generation", value: String(generation ?? 0)),
      URLQueryItem(name: "threadId", value: threadId ?? "")
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

  private func waitForSocket(_ task: URLSessionWebSocketTask) async {
    for _ in 0..<50 {
      if task.state == .running {
        setStatus("已连接")
        retryAttempt = 0
        startReceiveLoop(task)
        return
      }
      if task.state == .completed || task.state == .canceling { break }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    setStatus("连接失败")
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
            self.setStatus("设备已撤销，请重新配对")
            self.onCredentialsRevoked?()
            return
          }
          self.setStatus("连接中断")
          self.onDisconnect?()
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

  private func handle(_ text: String) {
    guard let data = text.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    if let id = message["id"] as? String, let waiter = pending.removeValue(forKey: id) {
      waiter.timeoutTask?.cancel()
      if message["kind"] as? String == "error", let payload = nativeDictionary(message["payload"]) {
        waiter.continuation.resume(throwing: NativeBridgeError.rpc(code: nativeString(payload["code"]) ?? "rpc.error", message: nativeString(payload["message"]) ?? "请求失败", requestId: id))
      } else {
        waiter.continuation.resume(returning: message)
      }
      return
    }
    onMessage?(message)
  }

  private func setStatus(_ value: String) {
    status = value
    onStatusChange?(value)
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
    guard SHA256.hex(data) == expected else {
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
