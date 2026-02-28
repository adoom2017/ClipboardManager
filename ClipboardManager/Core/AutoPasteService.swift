import Foundation
import AppKit
import ApplicationServices

class AutoPasteService {
    static let shared = AutoPasteService()

    /// 记录上一个活跃的非本应用 App
    private(set) var previousApp: NSRunningApplication?
    private var appObserver: Any?
    /// 本次会话是否已经提示过权限问题
    private var hasShownPermissionHint = false

    private init() {
        startTrackingFrontmostApp()
    }

    deinit {
        if let observer = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - 跟踪前台应用

    private func startTrackingFrontmostApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontApp
        }

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }
            self?.previousApp = app
        }
    }

    // MARK: - 自动粘贴

    func autoPaste(item: ClipboardItem) {
        // 无辅助功能权限时，直接提示引导，不尝试粘贴
        guard AXIsProcessTrusted() else {
            showAccessibilityPermissionAlert()
            return
        }

        // 1. 根据类型写入剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text:
            pasteboard.setString(item.content, forType: .string)
        case .image:
            guard let imageName = item.imageName,
                  let image = PersistenceController.shared.loadImage(named: imageName) else {
                print("[AutoPaste] 图片文件不存在")
                return
            }
            pasteboard.setClipboardImage(image)
        case .file:
            guard let urlStrings = item.fileURLs else { return }
            let urls = urlStrings.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { return }
            pasteboard.setClipboardFileURLs(urls)
        }

        // 2. 记住目标应用（含 PID，用于直接投递事件）
        let targetApp = previousApp
        let targetPID = targetApp?.processIdentifier

        // 3. 关闭所有面板
        dismissAllPanels()

        // 4. 激活目标应用并粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let app = targetApp {
                app.activate()
            }
            // 等待目标应用真正成为 frontmost，再发送 Cmd+V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performPaste(targetPID: targetPID)
            }
        }
    }

    func pasteAsPlainText(content: String) {
        let item = ClipboardItem(contentType: .text, content: content)
        autoPaste(item: item)
    }

    // MARK: - 粘贴实现

    /// 直接尝试粘贴，不做预检查
    private func performPaste(targetPID: pid_t? = nil) {
        // 方式 1：CGEvent（速度快，最直接）
        if pasteViaCGEvent(targetPID: targetPID) {
            print("[AutoPaste] CGEvent 粘贴成功")
            return
        }

        // 方式 2：AppleScript（备选）
        if pasteViaAppleScript() {
            print("[AutoPaste] AppleScript 粘贴成功")
            return
        }

        // 两种方式都失败，仅提示一次
        print("[AutoPaste] 所有粘贴方式都失败")
        if !hasShownPermissionHint {
            hasShownPermissionHint = true
            showAccessibilityPermissionAlert()
        }
    }

    /// 通过 CGEvent 模拟 Cmd+V
    /// - 优先用 postToPid 直接投递给目标进程（无需 frontmost）
    /// - 降级到全局 HID tap
    private func pasteViaCGEvent(targetPID: pid_t? = nil) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            print("[AutoPaste] CGEvent 创建失败")
            return false
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        if let pid = targetPID {
            // 直接投递给目标进程，不依赖 frontmost 状态
            vDown.postToPid(pid)
            vUp.postToPid(pid)
        } else {
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
        }
        return true
    }

    /// 通过 AppleScript 模拟 Cmd+V
    private func pasteViaAppleScript() -> Bool {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("[AutoPaste] AppleScript 失败: \(error)")
            return false
        }
        return true
    }

    /// 引导用户授权辅助功能权限（启动检测 + 粘贴失败时调用）
    func showAccessibilityPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "ClipboardManager 需要「辅助功能」权限才能自动粘贴内容。\n\n请按以下步骤授权：\n1. 点击「打开系统设置」\n2. 找到 ClipboardManager，打开开关\n3. 重启 ClipboardManager"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后再说")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
        }
    }

    // MARK: - Private

    private func dismissAllPanels() {
        if FloatingPanelController.shared.isVisible {
            FloatingPanelController.shared.hidePanel()
        }
        for window in NSApp.windows {
            if window.isVisible && window !== FloatingPanelController.shared {
                if window.level != .normal && !(window is FloatingPanelController) {
                    window.orderOut(nil)
                }
            }
        }
    }
}