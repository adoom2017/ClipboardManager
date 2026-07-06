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

            ScrollView {
                previewContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 80, maxHeight: 320)
            .adaptiveGlassSurface(cornerRadius: 12)

            HStack {
                Text("来源: \(clipboardItem.sourceApp)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(clipboardItem.relativeTimeString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 360)
        .padding(14)
        .background(.ultraThinMaterial)
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
    private var previewContent: some View {
        switch clipboardItem.contentType {
        case .text:
            Text(clipboardItem.content)
                .font(.body)
                .textSelection(.enabled)
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        case .file:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(clipboardItem.fileURLs ?? [], id: \.self) { urlString in
                    Text(URL(string: urlString)?.path ?? urlString)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
