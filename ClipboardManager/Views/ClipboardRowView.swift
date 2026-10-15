import SwiftUI

struct ClipboardRowView: View {
    let clipboardItem: ClipboardItem
    var isHovered = false
    var isSelected = false
    var onActivate: (() -> Void)?
    var onActionHoverChanged: ((Bool) -> Void)?
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var thumbnail: NSImage?
    @ObservedObject private var syncService = SyncService.shared

    private static let cornerRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { onActivate?() }) {
                HStack(spacing: 10) {
                    leadingView

                    VStack(alignment: .leading, spacing: 2) {
                        Text(clipboardItem.contentPreview)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Text(metadata)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.78)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            trailingAccessories
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .task(id: clipboardItem.id) {
            guard clipboardItem.contentType == .image, let name = clipboardItem.imageName else { return }
            thumbnail = await Task.detached(priority: .utility) {
                PersistenceController.shared.loadImage(named: name)
            }.value
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowFill: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor)
        }
        return isHovered ? Color.primary.opacity(0.07) : .clear
    }

    private var metadata: String {
        let source = clipboardItem.sourceApp.isEmpty ? "未知来源" : clipboardItem.sourceApp
        return "\(source) · \(clipboardItem.relativeTimeString)"
    }

    private var accessoryColor: Color {
        isSelected ? .white.opacity(0.85) : .secondary
    }

    /// 操作按钮常驻布局、仅切换透明度，悬停时文字不会重新换行。
    private var trailingAccessories: some View {
        ZStack(alignment: .trailing) {
            if clipboardItem.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                    .rotationEffect(.degrees(45))
                    .padding(.trailing, 6)
                    .opacity(isHovered ? 0 : 1)
                    .accessibilityLabel("已置顶")
            }

            HStack(spacing: 0) {
                if clipboardItem.contentType == .text {
                    rowAction(systemImage: "character.bubble", helpText: "翻译") {
                        TranslationWindowController.shared.show(text: clipboardItem.content)
                    }
                    syncAction
                }

                rowAction(
                    systemImage: clipboardItem.isPinned ? "pin.slash" : "pin",
                    helpText: clipboardItem.isPinned ? "取消置顶" : "置顶"
                ) {
                    onPin?()
                }

                rowAction(systemImage: "trash", helpText: "删除") {
                    onDelete?()
                }
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)
            .onHover { hovering in
                onActionHoverChanged?(hovering)
            }
        }
    }

    private func rowAction(
        systemImage: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(accessoryColor)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    @ViewBuilder
    private var syncAction: some View {
        let peers = syncService.discoveredPeers
        if peers.count == 1, let peer = peers.first {
            rowAction(systemImage: "arrow.triangle.2.circlepath", helpText: "同步到 \(peer.displayName)") {
                syncService.syncItem(clipboardItem, to: peer)
            }
        } else if !peers.isEmpty {
            Menu {
                ForEach(peers) { peer in
                    Button(peer.displayName) {
                        syncService.syncItem(clipboardItem, to: peer)
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(accessoryColor)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("选择同步目标")
            .accessibilityLabel("选择同步目标")
        }
    }

    @ViewBuilder
    private var leadingView: some View {
        switch clipboardItem.contentType {
        case .text:
            typeIcon(systemImage: "text.alignleft", tint: .blue)
        case .image:
            imageThumbnail
        case .file:
            typeIcon(systemImage: fileIconName, tint: .purple)
        }
    }

    private func typeIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .white : tint)
            .frame(width: 30, height: 30)
            .background(
                isSelected ? Color.white.opacity(0.2) : tint.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var imageThumbnail: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.green.opacity(0.13))
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(.rect(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
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
