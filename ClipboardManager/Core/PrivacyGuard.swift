import Foundation

class PrivacyGuard {
    private var sensitiveApps: Set<String> = ["1Password", "Keychain Access", "LastPass", "Bitwarden"]
    private var storedData: String?

    func shouldRecordClipboardContent(from appName: String) -> Bool {
        return !sensitiveApps.contains(appName)
    }

    func isSensitive(data: String) -> Bool {
        // 简单的敏感数据检测：检查是否包含常见密码模式
        let patterns = ["password", "secret", "token", "api_key", "apikey", "private_key"]
        let lowered = data.lowercased()
        return patterns.contains { lowered.contains($0) }
    }

    func encryptSensitiveContent(_ content: String) -> String {
        // 占位加密逻辑
        return "Encrypted: \(content)"
    }

    func handleClipboardContent(_ content: String, from appName: String) -> String {
        if shouldRecordClipboardContent(from: appName) {
            return content
        } else {
            return encryptSensitiveContent(content)
        }
    }

    func storeData(_ data: String) {
        // 如果数据被检测为敏感数据，则不存储
        if isSensitive(data: data) {
            storedData = nil
        } else {
            storedData = data
        }
    }

    func retrieveData() -> String? {
        return storedData
    }
}