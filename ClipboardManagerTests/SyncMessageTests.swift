import XCTest
@testable import ClipboardManager

final class SyncMessageTests: XCTestCase {
    func testFrameHasBigEndianLengthHeader() throws {
        let message = SyncMessage(type: .ping, senderID: "device-a", senderName: "Mac")
        let frame = try message.toFrameData()

        let length = frame.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        XCTAssertEqual(length, frame.count - 4)
        XCTAssertEqual(try SyncMessage.from(body: frame.dropFirst(4)).type, .ping)
    }

    func testRejectsFrameAtSizeLimit() {
        var message = SyncMessage(type: .items, senderID: "device-a", senderName: "Mac")
        // Base64 编码后 JSON body 必然超过上限。
        message.encryptedPayload = Data(count: SyncMessage.maxBodyLength)

        XCTAssertThrowsError(try message.toFrameData()) { error in
            XCTAssertEqual(error as? SyncMessageError, .frameTooLarge)
        }
    }
}
