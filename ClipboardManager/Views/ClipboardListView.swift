import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    @ObservedObject private var syncService = SyncService.shared
    @State private var hoveredItemId: UUID?

    var body: some View {
        // 使用 ScrollView + LazyVStack 替代 List，避免 NSTableView 在
        // MenuBarExtra 窗口中引发约束更新无限循环导致崩溃的已知 SwiftUI bug
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                    ClipboardRowView(
                        clipboardItem: item,
                        shortcutIndex: nil,
                        isHovered: hoveredItemId == item.id,
                        onPin: { viewModel.togglePin(item) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.pasteItem(item)
                    }
                    .onHover { hovering in
                        hoveredItemId = hovering ? item.id : nil
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
                                        Button(peer.name) {
                                            SyncService.shared.syncItem(item, to: peer)
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            viewModel.deleteItem(item)
                        }
                    }

                    if index < viewModel.filteredItems.count - 1 {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 4)
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
    }
}

struct ClipboardListView_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardListView(viewModel: ClipboardListViewModel())
            .frame(width: 350, height: 400)
    }
}
