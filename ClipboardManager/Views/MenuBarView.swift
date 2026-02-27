import SwiftUI

struct MenuBarView: View {
    @ObservedObject var clipboardListViewModel: ClipboardListViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            SearchBarView(searchText: $clipboardListViewModel.searchText)
                .padding(.top, 8)

            Divider()
                .padding(.vertical, 4)

            // 剪贴板列表
            ClipboardListView(viewModel: clipboardListViewModel)

            Divider()
                .padding(.vertical, 4)

            // 底部操作栏
            HStack {
                Button("清空历史") {
                    clipboardListViewModel.clearAllItems()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .font(.caption)

                Spacer()

                Button(action: {
                    NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
                }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}