import XCTest
@testable import ClipboardManager

final class ClipboardSelectionControllerTests: XCTestCase {
    private let items = [
        ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, content: "first"),
        ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, content: "second"),
        ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, content: "third")
    ]

    func testDefaultsToFirstVisibleItem() {
        let selection = ClipboardSelectionController()

        XCTAssertEqual(selection.selectedID(in: items), items[0].id)
    }

    func testMovesSelectionWithinBounds() {
        var selection = ClipboardSelectionController()

        XCTAssertEqual(selection.move(in: items, by: 1), items[1].id)
        XCTAssertEqual(selection.move(in: items, by: 1), items[2].id)
        XCTAssertEqual(selection.move(in: items, by: 1), items[2].id)
        XCTAssertEqual(selection.move(in: items, by: -1), items[1].id)
    }

    func testPreservesSelectionByIDWhenItemsReorder() {
        var selection = ClipboardSelectionController()
        selection.select(items[1].id)

        XCTAssertEqual(selection.selectedID(in: [items[1], items[0], items[2]]), items[1].id)
    }

    func testFallsBackWhenSelectedItemDisappears() {
        var selection = ClipboardSelectionController()
        selection.select(items[1].id)

        XCTAssertEqual(selection.selectedID(in: [items[2], items[0]]), items[2].id)
        XCTAssertNil(selection.selectedID(in: []))
    }
}
