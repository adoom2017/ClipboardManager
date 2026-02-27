import XCTest
@testable import ClipboardManager

final class ClipboardStoreTests: XCTestCase {

    var clipboardStore: ClipboardStore!

    override func setUpWithError() throws {
        super.setUp()
        clipboardStore = ClipboardStore(inMemory: true)
    }

    override func tearDownWithError() throws {
        clipboardStore.clearAll()
        clipboardStore = nil
        super.tearDown()
    }

    func testAddClipboardItem() throws {
        let item = ClipboardItem(content: "Test String", sourceApp: "TestApp")
        clipboardStore.add(item)

        let items = clipboardStore.fetchAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "Test String")
    }

    func testFetchAllItems() throws {
        let item1 = ClipboardItem(content: "First Item", sourceApp: "App1")
        let item2 = ClipboardItem(content: "Second Item", sourceApp: "App2")
        clipboardStore.add(item1)
        clipboardStore.add(item2)

        let items = clipboardStore.fetchAll()
        XCTAssertEqual(items.count, 2)
    }

    func testClearAllItems() throws {
        let item = ClipboardItem(content: "Item to be cleared", sourceApp: "App")
        clipboardStore.add(item)

        clipboardStore.clearAll()
        let items = clipboardStore.fetchAll()
        XCTAssertEqual(items.count, 0)
    }

    func testRemoveItem() throws {
        let item = ClipboardItem(content: "Item to remove", sourceApp: "App")
        clipboardStore.add(item)

        clipboardStore.remove(item)
        let items = clipboardStore.fetchAll()
        XCTAssertEqual(items.count, 0)
    }

    func testDuplicateHandling() throws {
        let item1 = ClipboardItem(content: "Same Content", sourceApp: "App1")
        let item2 = ClipboardItem(content: "Same Content", sourceApp: "App2")
        clipboardStore.add(item1)
        clipboardStore.add(item2)

        let items = clipboardStore.fetchAll()
        // 去重后应该只有一条
        XCTAssertEqual(items.count, 1)
    }
}