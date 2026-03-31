import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    private var isUpdatingLaunchAtLogin = false

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
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            guard launchAtLoginEnabled != oldValue else { return }

            do {
                try LaunchAtLoginManager.shared.setEnabled(launchAtLoginEnabled)
                launchAtLoginErrorMessage = nil
                UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
            } catch {
                isUpdatingLaunchAtLogin = true
                launchAtLoginEnabled = oldValue
                isUpdatingLaunchAtLogin = false
                launchAtLoginErrorMessage = "开机启动设置失败：\(error.localizedDescription)"
            }
        }
    }
    @Published var launchAtLoginErrorMessage: String? = nil

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
        let launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        defaults.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
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
        launchAtLoginEnabled = false
        translationAPIURL = "https://api.openai.com/v1"
        translationAPIKey = ""
        translationModel = "gpt-4o-mini"
    }

    var launchAtLoginHint: String {
        if LaunchAtLoginManager.shared.requiresApproval {
            return "已请求开机启动。如未生效，请前往“系统设置 > 通用 > 登录项”确认允许。"
        }
        return "开启后，应用会在你登录 macOS 时自动启动。"
    }

    func clearLaunchAtLoginError() {
        launchAtLoginErrorMessage = nil
    }
}
