import Foundation
import Carbon
import AppKit
import Combine

// MARK: - 快捷键配置模型

struct ShortcutKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// 显示用的文字描述，如 "⌥V"
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    /// 默认快捷键: Option + V
    static let defaultShortcut = ShortcutKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey))

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        return keyMap[keyCode] ?? "?"
    }

    /// 将 NSEvent 修饰键映射到 Carbon 修饰键
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        return carbonMods
    }
}

// MARK: - 快捷键管理器

class KeyboardShortcutManager: ObservableObject {
    static let shared = KeyboardShortcutManager()

    @Published var currentShortcut: ShortcutKey {
        didSet {
            saveShortcut()
            reRegister()
        }
    }

    /// 是否正在录制新快捷键
    @Published var isRecording: Bool = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?

    init() {
        // 从 UserDefaults 加载保存的快捷键
        if let data = UserDefaults.standard.data(forKey: "globalShortcut"),
           let saved = try? JSONDecoder().decode(ShortcutKey.self, from: data) {
            self.currentShortcut = saved
        } else {
            self.currentShortcut = ShortcutKey.defaultShortcut
        }
        registerGlobalShortcut()
    }

    deinit {
        unregisterGlobalShortcut()
        stopRecording()
    }

    // MARK: - 录制快捷键

    func startRecording() {
        isRecording = true
        // 暂时取消注册，防止录制时触发
        unregisterGlobalShortcut()

        // 监听按键事件
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            let modifiers = ShortcutKey.carbonModifiers(from: event.modifierFlags)

            // 必须至少有一个修饰键（Cmd/Option/Control/Shift）
            guard modifiers != 0 else { return event }

            // Escape 取消录制
            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecording()
                self.registerGlobalShortcut()
                return nil
            }

            let newShortcut = ShortcutKey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            self.currentShortcut = newShortcut
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    func resetToDefault() {
        currentShortcut = ShortcutKey.defaultShortcut
    }

    // MARK: - 注册/注销

    private func reRegister() {
        unregisterGlobalShortcut()
        registerGlobalShortcut()
    }

    private func registerGlobalShortcut() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x434C4950) // 'CLIP'
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        let handlerBlock: EventHandlerUPP = { _, event, _ -> OSStatus in
            DispatchQueue.main.async {
                KeyboardShortcutManager.handleHotKey()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerBlock,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        RegisterEventHotKey(
            currentShortcut.keyCode,
            currentShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterGlobalShortcut() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private static func handleHotKey() {
        FloatingPanelController.shared.togglePanel()
    }

    private func saveShortcut() {
        if let data = try? JSONEncoder().encode(currentShortcut) {
            UserDefaults.standard.set(data, forKey: "globalShortcut")
        }
    }
}