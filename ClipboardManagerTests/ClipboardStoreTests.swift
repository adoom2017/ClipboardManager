import XCTest
@testable import ClipboardManager

final class ClipboardStoreTests: XCTestCase {

    var clipboardStore: ClipboardStore!

    override func setUpWithError() throws {
        super.setUp()
        clipboardStore = ClipboardStore(inMemory: true)
    }

    override func tearDownWithError() throws {
        clipboardStore = nil
        super.tearDown()
    }

    func testAddClipboardItem() throws {
        let item = ClipboardItem(content: "Test String", sourceApp: "TestApp")
        clipboardStore.addItem(item)

        let items = clipboardStore.fetchAllItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "Test String")
    }

    func testFetchAllItems() throws {
        let item1 = ClipboardItem(content: "First Item", sourceApp: "App1")
        let item2 = ClipboardItem(content: "Second Item", sourceApp: "App2")
        clipboardStore.addItem(item1)
        clipboardStore.addItem(item2)

        let items = clipboardStore.fetchAllItems()
        XCTAssertEqual(items.count, 2)
    }

    func testClearAllItems() throws {
        let item = ClipboardItem(content: "Item to be cleared", sourceApp: "App")
        clipboardStore.addItem(item)

        clipboardStore.clearAllItems()
        let items = clipboardStore.fetchAllItems()
        XCTAssertEqual(items.count, 0)
    }

    func testRemoveItem() throws {
        let item = ClipboardItem(content: "Item to remove", sourceApp: "App")
        clipboardStore.addItem(item)

        clipboardStore.deleteItem(item)
        let items = clipboardStore.fetchAllItems()
        XCTAssertEqual(items.count, 0)
    }

    func testDuplicateHandling() throws {
        let item1 = ClipboardItem(content: "Same Content", sourceApp: "App1")
        let item2 = ClipboardItem(content: "Same Content", sourceApp: "App2")
        clipboardStore.addItem(item1)
        clipboardStore.addItem(item2)

        let items = clipboardStore.fetchAllItems()
        // 去重后应该只有一条
        XCTAssertEqual(items.count, 1)
    }

    func testInMemoryStoreUsesIsolatedPersistence() throws {
        clipboardStore.addItem(ClipboardItem(content: "isolated-test-value"))

        XCTAssertTrue(clipboardStore.usesInMemoryPersistence)
        XCTAssertEqual(clipboardStore.fetchAllItems().map(\.content), ["isolated-test-value"])
    }

    func testRetentionRemovesExpiredUnpinnedItems() throws {
        let oldItem = ClipboardItem(
            content: "expired",
            timestamp: Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        )
        let pinnedItem = ClipboardItem(
            content: "pinned",
            timestamp: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
            isPinned: true
        )
        clipboardStore.addItem(oldItem)
        clipboardStore.addItem(pinnedItem)
        UserDefaults.standard.set(7, forKey: "retainDuration")
        defer { UserDefaults.standard.removeObject(forKey: "retainDuration") }

        clipboardStore.applyRetentionPolicy()

        XCTAssertEqual(clipboardStore.fetchAllItems().map(\.content), ["pinned"])
    }
}
