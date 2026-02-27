import SwiftUI

struct PreviewPopover: View {
    var clipboardItem: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(clipboardItem.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: 300)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            HStack {
                Text("来源: \(clipboardItem.sourceApp)")
                    .font(.footnote)
                    .foregroundColor(.gray)
                Spacer()
                Text(clipboardItem.relativeTimeString)
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
        }
        .frame(width: 320)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}