import Foundation
import Security

final class SecureCredentialStore {
    static let shared = SecureCredentialStore()

    private let service = Bundle.main.bundleIdentifier ?? "com.clipboard.ClipboardManager"

    private init() {}

    func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setValue(_ value: String, for account: String) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            SecItemDelete(key as CFDictionary)
            return
        }

        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(key as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = key
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
