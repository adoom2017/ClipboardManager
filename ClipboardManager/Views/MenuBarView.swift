import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var clipboardListViewModel: ClipboardListViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        // 圆角材质由 FloatingPanelController 的原生背景视图提供，
        // 这里只负责内容布局，不再叠加第二层材质。
        VStack(spacing: 0) {
            header
            Divider()
            ClipboardListView(viewModel: clipboardListViewModel)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .clipboardPanelDidShow)) { _ in
            isSearchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("搜索剪贴板历史", text: $clipboardListViewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)

            if !clipboardListViewModel.searchText.isEmpty {
                Button {
                    clipboardListViewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }

            moreMenu
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(WindowDragArea())
    }

    private var moreMenu: some View {
        Menu {
            Button("设置…", action: openSettingsWindow)
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("退出 ClipboardManager") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多")
        .accessibilityLabel("更多")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(clipboardListViewModel.filteredItems.count) 项")
                .contentTransition(.numericText())

            Spacer(minLength: 8)

            KeyHint(keys: "↑↓", label: "选择")
            KeyHint(keys: "↩", label: "粘贴")
            KeyHint(keys: "esc", label: "关闭")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(WindowDragArea())
    }

    private func openSettingsWindow() {
        FloatingPanelController.shared.hidePanel()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        // Settings 场景可能在本次事件循环结束时才创建窗口。
        // 再次激活可确保菜单栏应用的新窗口成为 key window。
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { window in
                window.isVisible
                    && window !== FloatingPanelController.shared
                    && window.canBecomeKey
            })?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 16)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}
