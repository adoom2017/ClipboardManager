import Foundation
import AppKit

// MARK: - Content Type

enum ClipboardContentType: String, Codable {
    case text
    case image
    case file
}

// MARK: - Model

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID
    var contentType: ClipboardContentType
    var content: String        // text 内容 / 图片尺寸描述 / 文件名列表
    var timestamp: Date
    var sourceApp: String
    var isPinned: Bool
    var imageName: String?     // 图片保存到磁盘的文件名
    var fileURLs: [String]?    // 文件 URL 字符串数组

    init(
        id: UUID = UUID(),
        contentType: ClipboardContentType = .text,
        content: String,
        timestamp: Date = Date(),
        sourceApp: String = "Unknown",
        isPinned: Bool = false,
        imageName: String? = nil,
        fileURLs: [String]? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.content = content
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.imageName = imageName
        self.fileURLs = fileURLs
    }

    // 旧 JSON 数据没有 contentType / imageName / fileURLs 字段，用默认值兼容
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,   forKey: .id)
        contentType = try c.decodeIfPresent(ClipboardContentType.self, forKey: .contentType) ?? .text
        content     = try c.decode(String.self, forKey: .content)
        timestamp   = try c.decode(Date.self,   forKey: .timestamp)
        sourceApp   = try c.decode(String.self, forKey: .sourceApp)
        isPinned    = try c.decode(Bool.self,   forKey: .isPinned)
        imageName   = try c.decodeIfPresent(String.self,   forKey: .imageName)
        fileURLs    = try c.decodeIfPresent([String].self, forKey: .fileURLs)
    }

    // MARK: - Computed

    var contentPreview: String {
        switch contentType {
        case .text:
            let lines = content.components(separatedBy: .newlines).prefix(2)
            let preview = lines.joined(separator: " ")
            return preview.count > 100 ? String(preview.prefix(100)) + "…" : preview
        case .image, .file:
            return content
        }
    }

    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}