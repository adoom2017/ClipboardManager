import AppKit
import SwiftUI

/// 管理翻译弹窗的生命周期（复用单个 NSWindow）
class TranslationWindowController: NSObject, NSWindowDelegate {
    static let shared = TranslationWindowController()
    private var window: NSWindow?

    private override init() {}

    func show(text: String) {
        if let existing = window, existing.isVisible {
            existing.close()
        }

        let hostingView = NSHostingView(rootView: TranslationWindowView(originalText: text))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // 禁止 NSHostingView 根据 SwiftUI 内容尺寸变化驱动窗口约束更新，
        // 避免 ScrollView 动态行高引发的约束递归崩溃
        hostingView.sizingOptions = []

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 400))
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "翻译"
        win.contentView = container
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
