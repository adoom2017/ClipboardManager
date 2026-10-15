import SwiftUI
import Combine

class ClipboardListViewModel: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var searchText: String = "" {
        didSet { selection.reset() }
    }
    @Published private var selection = ClipboardSelectionController()
    private var cancellables = Set<AnyCancellable>()

    /// 过滤后的列表（支持搜索）
    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardItems
        }
        return clipboardItems.filter {
            $0.content.localizedCaseInsensitiveContains(searchText) ||
            $0.sourceApp.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 当前高亮的条目；未手动选择时默认第一条，与回车粘贴的目标保持一致。
    var selectedItemID: UUID? {
        selection.selectedID(in: filteredItems)
    }

    init() {
        loadClipboardItems()
        observeStore()
    }

    private func loadClipboardItems() {
        clipboardItems = ClipboardStore.shared.fetchAllItems()
    }

    private func observeStore() {
        ClipboardStore.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.clipboardItems = items
            }
            .store(in: &cancellables)
    }

    func pasteItem(_ item: ClipboardItem) {
        AutoPasteService.shared.autoPaste(item: item)
    }

    func moveSelection(by offset: Int) {
        selection.move(in: filteredItems, by: offset)
    }

    func select(_ item: ClipboardItem) {
        selection.select(item.id)
    }

    func pasteSelectedItem() {
        guard let item = selection.selectedItem(in: filteredItems) else { return }
        pasteItem(item)
    }

    func deleteItem(_ item: ClipboardItem) {
        ClipboardStore.shared.deleteItem(item)
    }

    func clearAllItems() {
        ClipboardStore.shared.clearAllItems()
    }

    func togglePin(_ item: ClipboardItem) {
        ClipboardStore.shared.togglePin(item)
    }
}
