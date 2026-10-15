import Foundation

// MARK: - 消息类型

enum SyncMessageType: String, Codable {
    case hello            // 初次握手，携带设备名称
    case items            // 推送加密的剪贴板条目
    case ack              // 收到确认
    case ping             // 心跳
    case pong             // 心跳回应
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
