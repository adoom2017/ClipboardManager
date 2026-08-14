import Foundation

struct ClipboardSelectionController {
    private(set) var selectedItemID: UUID?

    func selectedItem(in items: [ClipboardItem]) -> ClipboardItem? {
        guard let first = items.first else { return nil }
        guard let selectedItemID else { return first }
        return items.first(where: { $0.id == selectedItemID }) ?? first
    }

    func selectedID(in items: [ClipboardItem]) -> UUID? {
        selectedItem(in: items)?.id
    }

    @discardableResult
    mutating func move(in items: [ClipboardItem], by offset: Int) -> UUID? {
        guard !items.isEmpty else {
            selectedItemID = nil
            return nil
        }

        let current = selectedItem(in: items) ?? items[0]
        let currentIndex = items.firstIndex(where: { $0.id == current.id }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        selectedItemID = items[nextIndex].id
        return selectedItemID
    }

    mutating func select(_ itemID: UUID) {
        selectedItemID = itemID
    }

    mutating func reset() {
        selectedItemID = nil
    }
}
