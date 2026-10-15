import Foundation

// MARK: - 消息类型

enum SyncMessageType: String, Codable {
    case hello            // 初次握手，携带设备名称
    case items            // 推送加密的剪贴板条目
    case ack              // 收到确认
    case ping             // 心跳
    case pong             // 心跳回应
    case error            // 接收端拒绝 items，携带 errorCode
}

/// `error` 消息的原因码。未知原因码按通用失败处理。
enum SyncErrorCode: String, Codable {
    case pinNotConfigured
    case decryptFailed
    case invalidPayload

    func userMessage(peerName: String) -> String {
        switch self {
        case .pinNotConfigured:
            return "\(peerName) 尚未配置同步 PIN。"
        case .decryptFailed:
            return "\(peerName) 无法解密，请确认两端同步 PIN 一致。"
        case .invalidPayload:
            return "\(peerName) 无法解析同步内容，请确认两端均为最新版本。"
        }
    }
}

// MARK: - 消息体

struct SyncMessage: Codable {
    var type: SyncMessageType
    /// 发送方设备唯一 ID（持久化 UUID）
    var senderID: String
    /// 发送方设备名称（可读）
    var senderName: String
    /// AES-GCM: nonce + ciphertext + tag
    var encryptedPayload: Data?
    /// 仅 `error` 消息使用，取值见 `SyncErrorCode`
    var errorCode: String?

    // MARK: 帧编解码（4 字节大端长度头 + JSON body）

    /// 单帧 body 长度上限（不含），两端收发都按此限制。
    static let maxBodyLength = 10_000_000

    func toFrameData() throws -> Data {
        let body = try JSONEncoder().encode(self)
        guard body.count < Self.maxBodyLength else {
            throw SyncMessageError.frameTooLarge
        }
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        return frame
    }

    static func from(body: Data) throws -> SyncMessage {
        return try JSONDecoder().decode(SyncMessage.self, from: body)
    }
}

enum SyncMessageError: LocalizedError {
    case frameTooLarge
    var errorDescription: String? { "同步内容过大" }
}

// MARK: - items payload（加密前的明文结构）

struct SyncItemsPayload: Codable {
    var items: [SyncClipboardItem]
}

struct SyncClipboardItem: Codable {
    var id: String
    var content: String
    var timestamp: Date
    var sourceApp: String
    var isPinned: Bool
}
