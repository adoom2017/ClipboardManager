import Foundation
import CryptoKit

/// AES-GCM 加解密 + HKDF 密钥派生工具
enum SyncCrypto {

    // MARK: - 密钥派生

    /// 从 6 位 PIN 码 + 双方设备 ID 派生 256-bit AES 对称密钥
    static func deriveKey(pin: String, localID: String, remoteID: String) -> SymmetricKey {
        // 将两个 ID 排序后拼接，保证双方派生结果一致
        let ids = [localID, remoteID].sorted().joined(separator: ":")
        let salt = Data((ids + ":" + pin).utf8)
        let ikm = SymmetricKey(data: Data("ClipboardManagerSync".utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("v1-sync-key".utf8),
            outputByteCount: 32
        )
    }

    // MARK: - 加密

    /// AES-GCM 加密，返回 nonce(12B) + ciphertext + tag 拼接后的 Data
    static func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        // combined = nonce + ciphertext + tag
        guard let combined = sealedBox.combined else {
            throw SyncCryptoError.encryptionFailed
        }
        return combined
    }

    // MARK: - 解密

    static func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - PIN 生成

    /// 生成 6 位数字 PIN
    static func generatePIN() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }
}

enum SyncCryptoError: LocalizedError {
    case encryptionFailed
    var errorDescription: String? { "加密失败" }
}
