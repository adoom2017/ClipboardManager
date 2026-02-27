import Foundation
import AppKit

/// JSON 文件持久化控制器，替代 Core Data
class PersistenceController {
    static let shared = PersistenceController()

    private let fileURL: URL
    private let imageDir: URL

    init(inMemory: Bool = false) {
        if inMemory {
            fileURL  = URL(fileURLWithPath: "/dev/null")
            imageDir = URL(fileURLWithPath: NSTemporaryDirectory())
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            fileURL  = appDir.appendingPathComponent("clipboard_history.json")
            imageDir = appDir.appendingPathComponent("Images", isDirectory: true)
            try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Items

    func loadItems() -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            print("Failed to load clipboard items: \(error)")
            return []
        }
    }

    func saveItems(_ items: [ClipboardItem]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save clipboard items: \(error)")
        }
    }

    // MARK: - Images

    /// 将 NSImage 保存为 PNG 文件，文件名如 "UUID.png"
    func saveImage(_ image: NSImage, named name: String) {
        let url = imageDir.appendingPathComponent(name)
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let png  = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }

    /// 从磁盘加载图片
    func loadImage(named name: String) -> NSImage? {
        NSImage(contentsOf: imageDir.appendingPathComponent(name))
    }

    /// 删除磁盘上的图片文件
    func deleteImage(named name: String) {
        try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(name))
    }
}