import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    @Published var maxHistoryCount: Int {
        didSet { UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount") }
    }
    @Published var retainDuration: Int {
        didSet { UserDefaults.standard.set(retainDuration, forKey: "retainDuration") }
    }
    @Published var isPrivacyModeEnabled: Bool {
        didSet { UserDefaults.standard.set(isPrivacyModeEnabled, forKey: "isPrivacyModeEnabled") }
    }
    @Published var isClipboardHistoryEnabled: Bool {
        didSet { UserDefaults.standard.set(isClipboardHistoryEnabled, forKey: "isClipboardHistoryEnabled") }
    }
    @Published var isPrivacyGuardEnabled: Bool {
        didSet { UserDefaults.standard.set(isPrivacyGuardEnabled, forKey: "isPrivacyGuardEnabled") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.maxHistoryCount = defaults.object(forKey: "maxHistoryCount") as? Int ?? 100
        self.retainDuration = defaults.object(forKey: "retainDuration") as? Int ?? 7
        self.isPrivacyModeEnabled = defaults.bool(forKey: "isPrivacyModeEnabled")
        self.isClipboardHistoryEnabled = defaults.object(forKey: "isClipboardHistoryEnabled") as? Bool ?? true
        self.isPrivacyGuardEnabled = defaults.bool(forKey: "isPrivacyGuardEnabled")
    }

    func clearHistory() {
        ClipboardStore.shared.clearAllItems()
    }

    func resetSettings() {
        maxHistoryCount = 100
        retainDuration = 7
        isPrivacyModeEnabled = false
        isClipboardHistoryEnabled = true
        isPrivacyGuardEnabled = false
    }
}