import Foundation

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    private let persistenceController = PersistenceController.shared
    @Published var items: [ClipboardItem] = []

    private init() {
        items = persistenceController.loadItems()
    }

    /// 方便测试用的内部初始化
    init(inMemory: Bool) {
        let controller = PersistenceController(inMemory: true)
        items = controller.loadItems()
    }

    // MARK: - CRUD Operations

    func addItem(_ item: ClipboardItem) {
        // 类型感知去重，同时清理被替换的图片文件
        let duplicates: [ClipboardItem]
        switch item.contentType {
        case .text:
            duplicates = items.filter { $0.content == item.content && $0.contentType == .text && !$0.isPinned }
        case .image:
            // 按尺寸描述去重（防止粘贴自身时反复记录）
            duplicates = items.filter { $0.content == item.content && $0.contentType == .image && !$0.isPinned }
        case .file:
            duplicates = items.filter { $0.fileURLs == item.fileURLs && !$0.isPinned }
        }
        deleteImageFiles(for: duplicates)
        items.removeAll { old in duplicates.contains { $0.id == old.id } }

        items.insert(item, at: pinnedCount)
        enforceLimit()
        save()
    }

    func saveItem(_ item: ClipboardItem) {
        addItem(item)
    }

    func fetchAllItems() -> [ClipboardItem] {
        return items
    }

    func deleteItem(_ item: ClipboardItem) {
        deleteImageFiles(for: [item])
        items.removeAll { $0.id == item.id }
        save()
    }

    func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func clearAllItems() {
        let toRemove = items.filter { !$0.isPinned }
        deleteImageFiles(for: toRemove)
        items.removeAll { !$0.isPinned }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        // 重新排序：置顶的在前
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + unpinned
        save()
    }

    func fetchAll() -> [ClipboardItem] {
        return items
    }

    func add(_ item: ClipboardItem) {
        addItem(item)
    }

    func remove(_ item: ClipboardItem) {
        deleteItem(item)
    }

    // MARK: - Private

    private var pinnedCount: Int {
        items.filter { $0.isPinned }.count
    }

    private func enforceLimit() {
        let maxItems = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        let limit = maxItems > 0 ? maxItems : Constants.maxHistoryItems
        let unpinned = items.filter { !$0.isPinned }
        if unpinned.count > limit {
            let excess = unpinned.count - limit
            let toRemove = Array(unpinned.suffix(excess))
            deleteImageFiles(for: toRemove)
            items.removeAll { item in toRemove.contains { $0.id == item.id } }
        }
    }

    /// 批量删除图片文件
    private func deleteImageFiles(for items: [ClipboardItem]) {
        for item in items where item.contentType == .image {
            if let name = item.imageName {
                PersistenceController.shared.deleteImage(named: name)
            }
        }
    }

    private func save() {
        persistenceController.saveItems(items)
    }
}