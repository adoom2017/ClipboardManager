import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    @ObservedObject private var syncService = SyncService.shared
    @State private var hoveredItemId: UUID?
    @State private var actionHoveredItemId: UUID?
    @State private var previewedItem: ClipboardItem?
    @State private var previewTask: Task<Void, Never>?
    @State private var dismissPreviewTask: Task<Void, Never>?
    @State private var selection = ClipboardSelectionController()
    @FocusState private var isListFocused: Bool

    private var selectedItemID: UUID? {
        selection.selectedID(in: viewModel.filteredItems)
    }

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
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    rows
                }
            }
            .onChange(of: selectedItemID) { _, itemID in
                guard let itemID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(itemID, anchor: .center)
                }
            }
        }
        .scrollIndicators(.hidden)
        .clipped()
        .focusable(interactions: .edit)
        .focused($isListFocused)
        .defaultFocus($isListFocused, true)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            pasteSelectedItem()
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelDidShow)) { _ in
            isListFocused = true
        }
        .onChange(of: viewModel.searchText) {
            selection.reset()
        }
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
        LazyVStack(spacing: 2) {
            ForEach(viewModel.filteredItems) { item in
                row(for: item)
                    .id(item.id)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func row(for item: ClipboardItem) -> some View {
        ClipboardRowView(
            clipboardItem: item,
            shortcutIndex: nil,
            isHovered: hoveredItemId == item.id,
            isKeyboardSelected: selectedItemID == item.id,
            onActivate: { viewModel.pasteItem(item) },
            onActionHoverChanged: { hovering in
                handleActionHover(hovering, item: item)
            },
            onPin: { viewModel.togglePin(item) },
            onDelete: { delete(item) }
        )
        .contentShape(.rect)
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

    private func moveSelection(by offset: Int) {
        selection.move(in: viewModel.filteredItems, by: offset)
    }

    private func pasteSelectedItem() {
        guard let item = selection.selectedItem(in: viewModel.filteredItems) else { return }
        viewModel.pasteItem(item)
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
            .frame(width: 360, height: 400)
    }
}
