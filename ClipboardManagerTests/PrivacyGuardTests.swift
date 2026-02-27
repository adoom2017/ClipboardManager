import XCTest
@testable import ClipboardManager

final class PrivacyGuardTests: XCTestCase {

    var privacyGuard: PrivacyGuard!

    override func setUpWithError() throws {
        privacyGuard = PrivacyGuard()
    }

    override func tearDownWithError() throws {
        privacyGuard = nil
    }

    func testSensitiveDataDetection() throws {
        let sensitiveData = "my_password123"
        let isSensitive = privacyGuard.isSensitive(data: sensitiveData)
        XCTAssertTrue(isSensitive, "应该检测到敏感数据")
    }

    func testNonSensitiveDataDetection() throws {
        let nonSensitiveData = "Hello, World!"
        let isSensitive = privacyGuard.isSensitive(data: nonSensitiveData)
        XCTAssertFalse(isSensitive, "不应该将普通数据识别为敏感")
    }

    func testSensitiveDataNotStored() throws {
        let sensitiveData = "api_key_12345"
        privacyGuard.storeData(sensitiveData)
        let storedData = privacyGuard.retrieveData()
        XCTAssertNil(storedData, "敏感数据不应被存储")
    }

    func testNonSensitiveDataStored() throws {
        let normalData = "Hello World"
        privacyGuard.storeData(normalData)
        let storedData = privacyGuard.retrieveData()
        XCTAssertEqual(storedData, normalData, "普通数据应该被存储")
    }

    func testSensitiveAppsBlocked() throws {
        XCTAssertFalse(privacyGuard.shouldRecordClipboardContent(from: "1Password"))
        XCTAssertFalse(privacyGuard.shouldRecordClipboardContent(from: "Keychain Access"))
    }

    func testNormalAppsAllowed() throws {
        XCTAssertTrue(privacyGuard.shouldRecordClipboardContent(from: "Safari"))
        XCTAssertTrue(privacyGuard.shouldRecordClipboardContent(from: "TextEdit"))
    }
}