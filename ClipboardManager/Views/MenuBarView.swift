import SwiftUI

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var clipboardListViewModel: ClipboardListViewModel

    var body: some View {
        panelContent
            .adaptiveGlassSurface(cornerRadius: 20)
            .clipShape(.rect(cornerRadius: 20))
    }

    private var panelContent: some View {
        // One continuous glass surface; content must not cover it with a
        // second material, opaque window color, or inset rounded card.
        VStack(spacing: 8) {
            topBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
            listSection
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            SearchBarView(searchText: $clipboardListViewModel.searchText)

            GlassIconButton(systemImage: "gearshape", helpText: "设置", action: openSettingsWindow)

            GlassIconButton(systemImage: "power", helpText: "退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .zIndex(1)
    }

    private var listSection: some View {
        VStack(spacing: 0) {
            Text("\(clipboardListViewModel.filteredItems.count) 条记录")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 28)

            Divider()
                .opacity(0.65)

            ClipboardListView(viewModel: clipboardListViewModel)
                .padding(4)
        }
        .frame(maxHeight: .infinity)
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
