import Cocoa
import SwiftUI

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
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        clipboardMonitor?.stopMonitoring()
    }
}