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

    // MARK: - 翻译设置
    @Published var translationAPIURL: String {
        didSet { UserDefaults.standard.set(translationAPIURL, forKey: "translationAPIURL") }
    }
    @Published var translationAPIKey: String {
        didSet { UserDefaults.standard.set(translationAPIKey, forKey: "translationAPIKey") }
    }
    @Published var translationModel: String {
        didSet { UserDefaults.standard.set(translationModel, forKey: "translationModel") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.maxHistoryCount = defaults.object(forKey: "maxHistoryCount") as? Int ?? 100
        self.retainDuration = defaults.object(forKey: "retainDuration") as? Int ?? 7
        self.isPrivacyModeEnabled = defaults.bool(forKey: "isPrivacyModeEnabled")
        self.isClipboardHistoryEnabled = defaults.object(forKey: "isClipboardHistoryEnabled") as? Bool ?? true
        self.isPrivacyGuardEnabled = defaults.bool(forKey: "isPrivacyGuardEnabled")
        self.translationAPIURL = defaults.string(forKey: "translationAPIURL") ?? "https://api.openai.com/v1"
        self.translationAPIKey = defaults.string(forKey: "translationAPIKey") ?? ""
        self.translationModel = defaults.string(forKey: "translationModel") ?? "gpt-4o-mini"
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
        translationAPIURL = "https://api.openai.com/v1"
        translationAPIKey = ""
        translationModel = "gpt-4o-mini"
    }
}