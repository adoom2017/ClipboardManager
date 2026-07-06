import Foundation

class PrivacyGuard {
    private var sensitiveApps: Set<String> = ["1Password", "Keychain Access", "LastPass", "Bitwarden"]
    func shouldRecordClipboardContent(from appName: String, content: String? = nil) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "isPrivacyGuardEnabled") as? Bool ?? true else { return true }
        guard !sensitiveApps.contains(where: { appName.localizedCaseInsensitiveContains($0) }) else {
            return false
        }
        guard let content else { return true }
        return !isSensitive(data: content)
    }

    func isSensitive(data: String) -> Bool {
        // 简单的敏感数据检测：检查是否包含常见密码模式
        let patterns = ["password", "secret", "token", "api_key", "apikey", "private_key"]
        let lowered = data.lowercased()
        return patterns.contains { lowered.contains($0) }
    }

}
