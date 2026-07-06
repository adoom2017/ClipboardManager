import SwiftUI

struct ClipboardRowView: View {
    let clipboardItem: ClipboardItem
    let shortcutIndex: Int?
    var isHovered = false
    var onActivate: (() -> Void)?
    var onActionHoverChanged: ((Bool) -> Void)?
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var thumbnail: NSImage?
    @ObservedObject private var syncService = SyncService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { onActivate?() }) {
                HStack(spacing: 10) {
                    leadingView

                    VStack(alignment: .leading, spacing: 4) {
                        Text(clipboardItem.contentPreview)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        HStack(spacing: 5) {
                            Text(clipboardItem.sourceApp.isEmpty ? "未知来源" : clipboardItem.sourceApp)
                            Circle()
                                .fill(.tertiary)
                                .frame(width: 2.5, height: 2.5)
                            Text(clipboardItem.relativeTimeString)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                if clipboardItem.contentType == .text {
                    rowAction(systemImage: "globe", helpText: "翻译") {
                        TranslationWindowController.shared.show(text: clipboardItem.content)
                    }
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)

                    syncAction
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                }

                rowAction(
                    systemImage: clipboardItem.isPinned ? "pin.fill" : "pin",
                    helpText: clipboardItem.isPinned ? "取消置顶" : "置顶",
                    tint: clipboardItem.isPinned ? .orange : nil
                ) {
                    onPin?()
                }
                .opacity(clipboardItem.isPinned || isHovered ? 1 : 0)
                .allowsHitTesting(clipboardItem.isPinned || isHovered)

                rowAction(systemImage: "trash", helpText: "删除", tint: isHovered ? .red : nil) {
                    onDelete?()
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(minWidth: clipboardItem.contentType == .text ? 96 : 50, alignment: .trailing)
            .contentShape(.rect)
            .onHover { hovering in
                onActionHoverChanged?(hovering)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : .clear)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.leading, 52)
        }
        .contentShape(.rect(cornerRadius: 10))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovered)
        .task(id: clipboardItem.id) {
            guard clipboardItem.contentType == .image, let name = clipboardItem.imageName else { return }
            thumbnail = await Task.detached(priority: .utility) {
                PersistenceController.shared.loadImage(named: name)
            }.value
        }
        .accessibilityElement(children: .contain)
    }

    private func rowAction(
        systemImage: String,
        helpText: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 22, height: 22)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.055) : .clear, in: Circle())
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.green.opacity(0.12))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(.rect(cornerRadius: 9))
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
