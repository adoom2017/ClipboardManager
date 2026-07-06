import SwiftUI

struct MenuBarView: View {
    @ObservedObject var clipboardListViewModel: ClipboardListViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color.clear,
                    Color.indigo.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            panelContent
        }
        .background(.ultraThinMaterial)
    }

    private var panelContent: some View {
        VStack(spacing: 10) {
            header
            SearchBarView(searchText: $clipboardListViewModel.searchText)
                .zIndex(1)
            ClipboardListView(viewModel: clipboardListViewModel)
            footer
        }
        .padding(10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .adaptiveGlassIconControl(tint: Color.accentColor.opacity(0.16))

            VStack(alignment: .leading, spacing: 1) {
                Text("剪贴板")
                    .font(.headline)
                Text("\(clipboardListViewModel.filteredItems.count) 条记录")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Text("⌥V")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .adaptiveGlassSurface(cornerRadius: 9)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var footer: some View {
        let content = HStack(spacing: 8) {
            Button(role: .destructive) {
                clipboardListViewModel.clearAllItems()
            } label: {
                Label("清空", systemImage: "trash")
                    .font(.caption.weight(.medium))
            }
            .help("清空未置顶的历史记录")

            Spacer()

            GlassIconButton(systemImage: "gearshape", helpText: "设置", usesGlass: false) {
                NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
            }

            GlassIconButton(systemImage: "power", helpText: "退出", usesGlass: false) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 42)

        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content
                .buttonStyle(.borderless)
                .adaptiveGlassSurface(cornerRadius: 14)
        }
    }
}
