import SwiftUI
import Combine

class ClipboardListViewModel: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var searchText: String = ""
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

    init() {
        loadClipboardItems()
        observeStore()
        setupClipboardMonitor()
    }

    private func loadClipboardItems() {
        clipboardItems = ClipboardStore.shared.fetchAllItems()
    }

    private func setupClipboardMonitor() {
        ClipboardMonitor.shared.$newClipboardContent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItem in
                guard let self = self else { return }
                // 去重
                self.clipboardItems.removeAll { $0.content == newItem.content && !$0.isPinned }
                let pinnedCount = self.clipboardItems.filter { $0.isPinned }.count
                self.clipboardItems.insert(newItem, at: pinnedCount)
            }
            .store(in: &cancellables)
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

    func deleteItem(_ item: ClipboardItem) {
        ClipboardStore.shared.deleteItem(item)
        clipboardItems.removeAll { $0.id == item.id }
    }

    func deleteItems(at offsets: IndexSet) {
        // 需要根据 filteredItems 映射到 clipboardItems
        let itemsToDelete = offsets.map { filteredItems[$0] }
        for item in itemsToDelete {
            ClipboardStore.shared.deleteItem(item)
            clipboardItems.removeAll { $0.id == item.id }
        }
    }

    func clearAllItems() {
        ClipboardStore.shared.clearAllItems()
        clipboardItems.removeAll { !$0.isPinned }
    }

    func togglePin(_ item: ClipboardItem) {
        ClipboardStore.shared.togglePin(item)
        clipboardItems = ClipboardStore.shared.fetchAllItems()
    }
}
