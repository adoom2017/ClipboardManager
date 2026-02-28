import Foundation

// MARK: - 消息类型

enum SyncMessageType: String, Codable {
    case hello            // 初次握手，携带设备名称
    case pairingRequest   // 申请配对
    case pairingPin       // 发送 PIN 确认码
    case pairingAck       // 配对完成确认
    case pairingReject    // 拒绝配对
    case items            // 推送剪贴板条目（加密 payload）
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
    /// 加密后的业务 payload（items 消息时有值）
    var encryptedPayload: Data?
    /// 明文小字段（pairing 阶段使用，不含敏感数据）
    var plainPayload: Data?

    // MARK: 帧编解码（4 字节大端长度头 + JSON body）

    func toFrameData() throws -> Data {
        let body = try JSONEncoder().encode(self)
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        return frame
    }

    static func from(body: Data) throws -> SyncMessage {
        return try JSONDecoder().decode(SyncMessage.self, from: body)
    }
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
