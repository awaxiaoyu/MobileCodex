import Foundation

struct NativeProject: Identifiable, Hashable {
  let id: String
  let label: String
  let branch: String?
}

struct NativeModel: Identifiable, Hashable {
  let id: String
  let label: String
  let efforts: [String]
}

struct NativeThread: Identifiable, Hashable {
  let id: String
  var title: String
  let projectId: String?
  let preview: String?
  var pinned: Bool
}

struct NativeMessage: Identifiable, Hashable {
  let id: String
  let turnId: String
  let role: Role
  var text: String

  enum Role: String, Hashable {
    case user
    case assistant
    case reasoning
    case plan
  }
}

struct NativeArtifact: Identifiable, Hashable {
  let id: String
  let name: String
  let size: Int
  let contentType: String
}

struct NativeApproval: Identifiable {
  let id: String
  let method: String
  let payload: [String: Any]
  let backendId: String?
  let generation: Int?
  let threadId: String?
  let turnId: String?
}

struct PendingRPC {
  let continuation: CheckedContinuation<[String: Any], Error>
  var timeoutTask: Task<Void, Never>?
}

struct NativeCredentials: Codable {
  let url: String
  let fingerprint: String
  let token: String
  let deviceId: String
  let deviceName: String
}

enum NativeBridgeError: LocalizedError {
  case invalidPairing
  case invalidFingerprint
  case disconnected
  case rpc(code: String, message: String, requestId: String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidPairing: return "配对信息无效，需要 wss://.../ws 地址。"
    case .invalidFingerprint: return "电脑证书 fingerprint 必须是 SHA-256。"
    case .disconnected: return "电脑尚未连接。"
    case let .rpc(_, message, requestId): return "\(message) (\(requestId))"
    case .invalidResponse: return "电脑返回的数据无效。"
    }
  }
}

func nativeString(_ value: Any?) -> String? {
  guard let value else { return nil }
  let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
  return text.isEmpty ? nil : text
}

func nativeDictionary(_ value: Any?) -> [String: Any]? {
  value as? [String: Any]
}

func nativeArray(_ value: Any?) -> [[String: Any]] {
  (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
}
