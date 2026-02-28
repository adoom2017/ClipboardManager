import Cocoa
import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var clipboardMonitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 初始化自动粘贴服务（开始跟踪前台应用）
        _ = AutoPasteService.shared

        // 启动剪贴板监听
        clipboardMonitor = ClipboardMonitor.shared
        clipboardMonitor?.startMonitoring()

        // 注册全局快捷键（使用单例）
        _ = KeyboardShortcutManager.shared

        // 检查辅助功能权限，未授权时触发系统弹窗（打包后首次运行需要）
        requestAccessibilityPermissionIfNeeded()

        // 启动局域网同步服务
        SyncService.shared.start()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        clipboardMonitor?.stopMonitoring()
        SyncService.shared.stop()
    }

    // MARK: - 辅助功能权限

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        // prompt: true 会让系统弹出「请求辅助功能访问权限」对话框
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // 同时弹出应用自己的引导弹窗，说明用途
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AutoPasteService.shared.showAccessibilityPermissionAlert()
        }
    }
}