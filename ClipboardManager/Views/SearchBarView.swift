import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("搜索剪贴板", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.28),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }
}
