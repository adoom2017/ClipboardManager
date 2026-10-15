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

    func testErrorMessageCarriesCodeAndOmitsItWhenNil() throws {
        var message = SyncMessage(type: .error, senderID: "device-a", senderName: "Mac")
        message.errorCode = SyncErrorCode.decryptFailed.rawValue
        let decoded = try SyncMessage.from(body: try message.toFrameData().dropFirst(4))
        XCTAssertEqual(decoded.type, .error)
        XCTAssertEqual(decoded.errorCode, "decryptFailed")

        let ping = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SyncMessage(type: .ping, senderID: "a", senderName: "A"))
        ) as? [String: Any]
        XCTAssertNil(ping?["errorCode"])
    }

    func testReceivedItemsDedupesByUUIDAndNormalizesFields() throws {
        let existing = UUID()
        let fresh = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let items = SyncService.receivedItems(
            from: [
                SyncClipboardItem(id: fresh.uuidString.lowercased(), content: "new", timestamp: .distantPast, sourceApp: "Notepad", isPinned: true),
                SyncClipboardItem(id: existing.uuidString, content: "old", timestamp: .distantPast, sourceApp: "Notepad", isPinned: false),
                SyncClipboardItem(id: fresh.uuidString, content: "replayed", timestamp: .distantPast, sourceApp: "Notepad", isPinned: false),
                SyncClipboardItem(id: UUID().uuidString, content: "echo", timestamp: .distantPast, sourceApp: "📡 Chrome", isPinned: false)
            ],
            existingIDs: [existing],
            now: now
        )

        let received = try XCTUnwrap(items)
        XCTAssertEqual(received.map(\.content), ["new", "echo"])
        XCTAssertEqual(received[0].id, fresh)
        XCTAssertFalse(received[0].isPinned)
        XCTAssertEqual(received[0].timestamp, now)
        XCTAssertLessThan(received[1].timestamp, now)
        XCTAssertEqual(received[0].sourceApp, "📡 Notepad")
        XCTAssertEqual(received[1].sourceApp, "📡 Chrome")
    }

    func testReceivedItemsRejectsBatchWithInvalidID() {
        let items = SyncService.receivedItems(
            from: [SyncClipboardItem(id: "not-a-uuid", content: "x", timestamp: Date(), sourceApp: "", isPinned: false)],
            existingIDs: []
        )
        XCTAssertNil(items)
    }
}
