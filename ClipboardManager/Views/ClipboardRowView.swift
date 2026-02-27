import SwiftUI

struct ClipboardRowView: View {
    var clipboardItem: ClipboardItem
    var shortcutIndex: Int?
    var isHovered: Bool = false
    var onPin: (() -> Void)? = nil

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // 左侧图片缩略图或文件图标
            leadingView

            // 右侧文字内容
            VStack(alignment: .leading, spacing: 2) {
                Text(clipboardItem.contentPreview)
                    .font(.system(.body, design: .default))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(clipboardItem.sourceApp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(clipboardItem.relativeTimeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 置顶按钮：已置顶时常驻，未置顶时 hover 显示
            if clipboardItem.isPinned || isHovered {
                Button(action: { onPin?() }) {
                    Image(systemName: clipboardItem.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(clipboardItem.isPinned ? .orange : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(clipboardItem.isPinned ? "取消置顶" : "置顶")
            }

            // 快捷键索引（前9条）
            if let index = shortcutIndex {
                Text("⌘\(index)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .task(id: clipboardItem.id) {
            // 异步加载图片缩略图，避免阻塞主线程
            guard clipboardItem.contentType == .image, let name = clipboardItem.imageName else { return }
            thumbnail = await Task.detached(priority: .utility) {
                PersistenceController.shared.loadImage(named: name)
            }.value
        }
    }

    // MARK: - Leading View

    @ViewBuilder
    private var leadingView: some View {
        switch clipboardItem.contentType {
        case .text:
            EmptyView()
        case .image:
            imageThumbnail
        case .file:
            fileIcon
        }
    }

    private var imageThumbnail: some View {
        Group {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 40)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
        }
    }

    private var fileIcon: some View {
        Image(systemName: fileIconName)
            .font(.title2)
            .foregroundColor(.accentColor)
            .frame(width: 32, alignment: .center)
    }

    private var fileIconName: String {
        guard let urlStrings = clipboardItem.fileURLs,
              let first = urlStrings.first,
              let url = URL(string: first) else { return "doc.fill" }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "film"
        case "mp3", "aac", "flac", "wav", "m4a", "ogg":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return "archivebox"
        case "app":
            return "app.badge"
        case "":
            return "folder"
        default:
            return "doc.fill"
        }
    }
}