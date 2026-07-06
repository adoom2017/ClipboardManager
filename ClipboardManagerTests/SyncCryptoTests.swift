import CryptoKit
import XCTest
@testable import ClipboardManager

final class SyncCryptoTests: XCTestCase {
    func testRoundTrip() throws {
        let key = SyncCrypto.deriveKey(pin: "123456", localID: "device-b", remoteID: "device-a")
        let plaintext = Data("跨平台 clipboard".utf8)
        let encrypted = try SyncCrypto.encrypt(
            plaintext,
            using: key,
            nonceData: Data(0..<12)
        )

        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertEqual(
            encrypted.base64EncodedString(),
            "AAECAwQFBgcICQoLr/gPlfdYHSW1MBcsXO1weTKZk0eqINLMK94uHAlAjw8lf/g="
        )
        XCTAssertEqual(try SyncCrypto.decrypt(encrypted, using: key), plaintext)
    }

    func testDeviceOrderDoesNotChangeDerivedKey() {
        let first = SyncCrypto.deriveKey(pin: "123456", localID: "a", remoteID: "b")
        let second = SyncCrypto.deriveKey(pin: "123456", localID: "b", remoteID: "a")

        XCTAssertEqual(first.withUnsafeBytes { Data($0) }, second.withUnsafeBytes { Data($0) })
    }
}
