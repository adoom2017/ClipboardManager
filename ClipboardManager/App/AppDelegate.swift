import Cocoa
import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var clipboardMonitor: ClipboardMonitor?
    private var statusItem: NSStatusItem?

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard !isRunningUnitTests else { return }
        AppLogger.shared.start()

        // 初始化自动粘贴服务（开始跟踪前台应用）
        _ = AutoPasteService.shared

        // 启动剪贴板监听
        clipboardMonitor = ClipboardMonitor.shared
        clipboardMonitor?.startMonitoring()

        // 注册全局快捷键（使用单例）
        _ = KeyboardShortcutManager.shared

        // 菜单栏图标与全局快捷键共用同一个浮动面板。
        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettingsRequest,
            object: nil
        )

        // 检查辅助功能权限，未授权时只触发系统弹窗。
        // 用户实际粘贴失败时，再由 AutoPasteService 显示应用内引导。
        requestAccessibilityPermissionIfNeeded()

        // 启动局域网同步服务
        SyncService.shared.start()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        guard !isRunningUnitTests else { return }
        NotificationCenter.default.removeObserver(self)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        clipboardMonitor?.stopMonitoring()
        SyncService.shared.stop()
    }

    // MARK: - Menu Bar

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }

        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "剪贴板"
        )?.withSymbolConfiguration(configuration)
        button.imagePosition = .imageOnly
        button.toolTip = "剪贴板"
        button.target = self
        button.action = #selector(toggleClipboardPanel)
        statusItem = item
    }

    @objc private func toggleClipboardPanel() {
        FloatingPanelController.shared.togglePanel()
    }

    @objc private func openSettings() {
        FloatingPanelController.shared.hidePanel()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - 辅助功能权限

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        // prompt: true 会让系统弹出「请求辅助功能访问权限」对话框
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
