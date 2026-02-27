import Foundation
import AppKit
import Combine

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published var clipboardItems: [ClipboardItem] = []
    @Published var newClipboardContent: ClipboardItem?

    private var cancellables = Set<AnyCancellable>()
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private let privacyGuard = PrivacyGuard()
    private var timer: AnyCancellable?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForNewClipboardContent()
            }
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    private func checkForNewClipboardContent() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let newItem = getClipboardContent() else { return }

        // 类型感知去重：仅检查最新一条
        let isDuplicate: Bool
        switch newItem.contentType {
        case .text:
            isDuplicate = clipboardItems.first?.content == newItem.content
        case .image:
            isDuplicate = false  // 每次 changeCount 变化都是真实的新图片
        case .file:
            isDuplicate = clipboardItems.first?.fileURLs == newItem.fileURLs
        }
        guard !isDuplicate else { return }

        clipboardItems.insert(newItem, at: 0)
        newClipboardContent = newItem
        ClipboardStore.shared.addItem(newItem)
    }

    private func getClipboardContent() -> ClipboardItem? {
        let sourceApp = getSourceApp()
        guard privacyGuard.shouldRecordClipboardContent(from: sourceApp) else { return nil }

        // 优先级 1：文件（Finder 复制）
        if let urls = pasteboard.getCurrentFileURLs(), !urls.isEmpty {
            let fileURLStrings = urls.map { $0.absoluteString }
            let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
            return ClipboardItem(contentType: .file, content: names,
                                 sourceApp: sourceApp, fileURLs: fileURLStrings)
        }

        // 优先级 2：原始图片数据（截图、从图片编辑器复制等）
        if pasteboard.availableType(from: [.tiff, .png]) != nil,
           let image = pasteboard.getCurrentImage() {
            let size = image.size
            let imageName = "\(UUID().uuidString).png"
            PersistenceController.shared.saveImage(image, named: imageName)
            let content = "[图片] \(Int(size.width))×\(Int(size.height))"
            return ClipboardItem(contentType: .image, content: content,
                                 sourceApp: sourceApp, imageName: imageName)
        }

        // 优先级 3：文本
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardItem(contentType: .text, content: text, sourceApp: sourceApp)
        }

        return nil
    }

    private func getSourceApp() -> String {
        return NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }
}