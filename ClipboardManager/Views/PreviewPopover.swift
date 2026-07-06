import SwiftUI
import AppKit

@MainActor
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private let panel: PreviewPanel
    private var currentItemID: UUID?

    private init() {
        panel = PreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
    }

    func show(
        item: ClipboardItem,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        let hostingView = NSHostingView(
            rootView: PreviewPopover(
                clipboardItem: item,
                onHoverChanged: onHoverChanged
            )
        )
        hostingView.autoresizingMask = [.width, .height]

        let fittingSize = hostingView.fittingSize
        let panelSize = NSSize(
            width: max(388, fittingSize.width),
            height: min(max(160, fittingSize.height), 420)
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
        panel.setFrame(
            NSRect(origin: panelOrigin(for: panelSize), size: panelSize),
            display: true
        )
        currentItemID = item.id
        panel.orderFrontRegardless()
    }

    func hide(itemID: UUID? = nil) {
        guard itemID == nil || currentItemID == itemID else { return }
        currentItemID = nil
        panel.orderOut(nil)
    }

    private func panelOrigin(for size: NSSize) -> NSPoint {
        let sourceFrame = FloatingPanelController.shared.frame
        let screenFrame = FloatingPanelController.shared.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? sourceFrame
        let gap: CGFloat = 8
        let preferredX = sourceFrame.maxX + gap
        let x = preferredX + size.width <= screenFrame.maxX
            ? preferredX
            : sourceFrame.minX - gap - size.width
        let mouseY = NSEvent.mouseLocation.y
        let unclampedY = mouseY - size.height / 2
        let y = min(
            max(unclampedY, screenFrame.minY),
            screenFrame.maxY - size.height
        )
        return NSPoint(x: x, y: y)
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct PreviewPopover: View {
    let clipboardItem: ClipboardItem
    var onHoverChanged: ((Bool) -> Void)?
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("完整内容")
                .font(.headline)

            HStack {
                Text(clipboardItem.sourceApp.isEmpty ? "未知来源" : clipboardItem.sourceApp)
                Spacer()
                Text(clipboardItem.relativeTimeString)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Divider()

            previewViewport
        }
        .frame(width: 360)
        .padding(14)
        .adaptiveGlassSurface(cornerRadius: 18, prominent: true)
        .clipShape(.rect(cornerRadius: 18))
        .padding(6)
        .onHover { hovering in
            onHoverChanged?(hovering)
        }
        .task(id: clipboardItem.id) {
            guard clipboardItem.contentType == .image,
                  let imageName = clipboardItem.imageName else { return }
            image = await Task.detached(priority: .utility) {
                PersistenceController.shared.loadImage(named: imageName)
            }.value
        }
    }

    @ViewBuilder
    private var previewViewport: some View {
        switch clipboardItem.contentType {
        case .text:
            ScrollView {
                Text(clipboardItem.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .frame(minHeight: 80, maxHeight: 320)
        case .image:
            if let image {
                GeometryReader { geometry in
                    ScrollView(.vertical) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(
                                width: geometry.size.width,
                                height: fittedImageHeight(
                                    imageSize: image.size,
                                    width: geometry.size.width
                                )
                            )
                            .accessibilityLabel("剪贴板图片完整预览")
                    }
                }
                .frame(height: 300)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(clipboardItem.fileURLs ?? [], id: \.self) { urlString in
                        Text(URL(string: urlString)?.path ?? urlString)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(minHeight: 80, maxHeight: 320)
        }
    }

    private func fittedImageHeight(imageSize: NSSize, width: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return width }
        return width * imageSize.height / imageSize.width
    }
}
