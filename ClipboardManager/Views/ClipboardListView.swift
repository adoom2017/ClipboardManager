import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    @ObservedObject private var syncService = SyncService.shared
    @State private var hoveredItemId: UUID?
    @State private var actionHoveredItemId: UUID?
    @State private var previewedItem: ClipboardItem?
    @State private var previewTask: Task<Void, Never>?
    @State private var dismissPreviewTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.filteredItems.isEmpty {
                    ContentUnavailableView(
                        viewModel.searchText.isEmpty ? "暂无剪贴板记录" : "没有匹配结果",
                        systemImage: viewModel.searchText.isEmpty ? "clipboard" : "magnifyingglass",
                        description: Text(
                            viewModel.searchText.isEmpty
                                ? "复制内容后会自动出现在这里"
                                : "尝试搜索其他关键词"
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    rows
                }
            }
            .onChange(of: viewModel.selectedItemID) { _, itemID in
                guard let itemID else { return }
                // 不指定锚点时只做最小滚动，选中项已可见则保持不动。
                proxy.scrollTo(itemID)
            }
        }
        .scrollIndicators(.automatic)
        .alert(
            "同步失败",
            isPresented: Binding(
                get: { syncService.syncErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        syncService.clearSyncError()
                    }
                }
            )
        ) {
            Button("确定") {
                syncService.clearSyncError()
            }
        } message: {
            Text(syncService.syncErrorMessage ?? "同步失败，请稍后重试。")
        }
        .onDisappear {
            previewTask?.cancel()
            dismissPreviewTask?.cancel()
            PreviewPanelController.shared.hide()
        }
    }

    private var rows: some View {
        let items = viewModel.filteredItems
        let pinned = items.filter(\.isPinned)
        let recent = items.filter { !$0.isPinned }

        return LazyVStack(alignment: .leading, spacing: 1) {
            if !pinned.isEmpty {
                sectionHeader("置顶")
                ForEach(pinned) { item in
                    row(for: item).id(item.id)
                }
                sectionHeader("最近")
            }
            ForEach(recent) { item in
                row(for: item).id(item.id)
            }
        }
        // 右侧留出滚动条通道：滚动条不压在行上，拖动时也不会误触行内按钮。
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(for item: ClipboardItem) -> some View {
        ClipboardRowView(
            clipboardItem: item,
            isHovered: hoveredItemId == item.id,
            isSelected: viewModel.selectedItemID == item.id,
            onActivate: {
                viewModel.select(item)
                viewModel.pasteItem(item)
            },
            onActionHoverChanged: { hovering in
                handleActionHover(hovering, item: item)
            },
            onPin: { viewModel.togglePin(item) },
            onDelete: { delete(item) }
        )
        .onHover { hovering in
            handleHover(hovering, item: item)
        }
        .contextMenu {
            Button(item.isPinned ? "取消置顶" : "置顶") {
                viewModel.togglePin(item)
            }
            if item.contentType == .text {
                Button("粘贴为纯文本") {
                    AutoPasteService.shared.pasteAsPlainText(content: item.content)
                }
                Button("翻译") {
                    TranslationWindowController.shared.show(text: item.content)
                }
                let peers = SyncService.shared.discoveredPeers
                if !peers.isEmpty {
                    Menu("同步到设备") {
                        ForEach(peers) { peer in
                            Button(peer.displayName) {
                                SyncService.shared.syncItem(item, to: peer)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("删除", role: .destructive) {
                delete(item)
            }
        }
    }

    private func delete(_ item: ClipboardItem) {
        previewTask?.cancel()
        dismissPreviewTask?.cancel()
        if hoveredItemId == item.id {
            hoveredItemId = nil
        }
        if actionHoveredItemId == item.id {
            actionHoveredItemId = nil
        }
        if previewedItem?.id == item.id {
            previewedItem = nil
            PreviewPanelController.shared.hide(itemID: item.id)
        }
        viewModel.deleteItem(item)
    }

    private func handleHover(_ hovering: Bool, item: ClipboardItem) {
        if hovering {
            hoveredItemId = item.id
            dismissPreviewTask?.cancel()
            schedulePreview(for: item)
        } else {
            if hoveredItemId == item.id {
                hoveredItemId = nil
            }
            if actionHoveredItemId == item.id {
                actionHoveredItemId = nil
            }
            previewTask?.cancel()
            schedulePreviewDismissal(for: item.id)
        }
    }

    private func handleActionHover(_ hovering: Bool, item: ClipboardItem) {
        if hovering {
            actionHoveredItemId = item.id
            previewTask?.cancel()
            dismissPreviewTask?.cancel()
            if previewedItem?.id == item.id {
                previewedItem = nil
                PreviewPanelController.shared.hide(itemID: item.id)
            }
        } else {
            if actionHoveredItemId == item.id {
                actionHoveredItemId = nil
            }
            if hoveredItemId == item.id {
                schedulePreview(for: item)
            }
        }
    }

    private func schedulePreview(for item: ClipboardItem) {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  hoveredItemId == item.id,
                  actionHoveredItemId != item.id else { return }
            previewedItem = item
            PreviewPanelController.shared.show(item: item) { hovering in
                if hovering {
                    dismissPreviewTask?.cancel()
                } else {
                    schedulePreviewDismissal(for: item.id)
                }
            }
        }
    }

    private func schedulePreviewDismissal(for itemID: UUID) {
        dismissPreviewTask?.cancel()
        dismissPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, hoveredItemId != itemID else { return }
            if previewedItem?.id == itemID {
                previewedItem = nil
                PreviewPanelController.shared.hide(itemID: itemID)
            }
        }
    }
}

struct ClipboardListView_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardListView(viewModel: ClipboardListViewModel())
            .frame(width: 400, height: 440)
    }
}
