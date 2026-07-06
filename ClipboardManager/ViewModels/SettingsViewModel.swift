import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    private var isUpdatingLaunchAtLogin = false

    @Published var maxHistoryCount: Int {
        didSet {
            UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount")
            ClipboardStore.shared.applyRetentionPolicy()
        }
    }
    @Published var retainDuration: Int {
        didSet {
            UserDefaults.standard.set(retainDuration, forKey: "retainDuration")
            ClipboardStore.shared.applyRetentionPolicy()
        }
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
        didSet { SecureCredentialStore.shared.setValue(translationAPIKey, for: "translationAPIKey") }
    }
    @Published var translationModel: String {
        didSet { UserDefaults.standard.set(translationModel, forKey: "translationModel") }
    }
    @Published var syncPIN: String {
        didSet {
            let normalized = String(syncPIN.filter(\.isNumber).prefix(6))
            if normalized != syncPIN {
                syncPIN = normalized
                return
            }
            SecureCredentialStore.shared.setValue(syncPIN, for: "syncPIN")
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.maxHistoryCount = defaults.object(forKey: "maxHistoryCount") as? Int ?? 100
        self.retainDuration = defaults.object(forKey: "retainDuration") as? Int ?? 7
        self.isClipboardHistoryEnabled = defaults.object(forKey: "isClipboardHistoryEnabled") as? Bool ?? true
        self.isPrivacyGuardEnabled = defaults.object(forKey: "isPrivacyGuardEnabled") as? Bool ?? true
        let launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        defaults.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
        self.translationAPIURL = defaults.string(forKey: "translationAPIURL") ?? "https://api.openai.com/v1"
        let legacyAPIKey = defaults.string(forKey: "translationAPIKey") ?? ""
        self.translationAPIKey = SecureCredentialStore.shared.value(for: "translationAPIKey") ?? legacyAPIKey
        if !legacyAPIKey.isEmpty {
            SecureCredentialStore.shared.setValue(legacyAPIKey, for: "translationAPIKey")
            defaults.removeObject(forKey: "translationAPIKey")
        }
        self.translationModel = defaults.string(forKey: "translationModel") ?? "gpt-4o-mini"
        self.syncPIN = SecureCredentialStore.shared.value(for: "syncPIN") ?? ""
    }

    func clearHistory() {
        ClipboardStore.shared.clearAllItems()
    }

    func resetSettings() {
        maxHistoryCount = 100
        retainDuration = 7
        isClipboardHistoryEnabled = true
        isPrivacyGuardEnabled = true
        launchAtLoginEnabled = false
        translationAPIURL = "https://api.openai.com/v1"
        translationAPIKey = ""
        translationModel = "gpt-4o-mini"
        syncPIN = ""
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
