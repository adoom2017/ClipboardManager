import SwiftUI
import AppKit

class FloatingPanelController: NSPanel {
    static let shared = FloatingPanelController()

    static let panelSize = NSSize(width: 400, height: 520)
    private static let cornerRadius: CGFloat = 16

    private let viewModel = ClipboardListViewModel()

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        // 只允许通过顶部搜索栏和底部状态栏的拖拽区域移动面板。
        // 背景可拖动会与列表滚动条抢占鼠标拖拽。
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.animationBehavior = .utilityWindow
        self.backgroundColor = .clear
        self.isOpaque = false
        // 窗口阴影跟随圆角背景的透明度轮廓。
        self.hasShadow = true
        // 允许面板在非活跃应用时也接收鼠标事件
        self.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: MenuBarView(clipboardListViewModel: viewModel))
        hostingView.sizingOptions = []
        self.contentView = Self.makeBackgroundView(containing: hostingView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 系统原生的圆角材质背景：macOS 26 使用 Liquid Glass，更早系统使用弹出层毛玻璃。
    /// SwiftUI 内容放在其中，不再自绘第二层材质。
    private static func makeBackgroundView(containing hostingView: NSView) -> NSView {
        let frame = NSRect(origin: .zero, size: panelSize)
        hostingView.frame = frame
        hostingView.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = hostingView
            return glass
        }

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(cornerRadius: cornerRadius)
        effect.addSubview(hostingView)
        return effect
    }

    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        // 显示在鼠标所在屏幕的偏上位置，接近 Spotlight 的视觉重心。
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        if let screenFrame = screen?.visibleFrame {
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.minY + (screenFrame.height - frame.height) * 0.62
            setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        }
        // 显示面板并立即成为 key window，使列表点击第一下即可响应
        // NSPanel 的 .nonactivatingPanel 保证不会激活（切换）当前前台应用
        orderFrontRegardless()
        makeKey()
        invalidateShadow()
        NotificationCenter.default.post(name: .clipboardPanelDidShow, object: nil)
    }

    func hidePanel() {
        PreviewPanelController.shared.hide()
        orderOut(nil)
    }

    // 允许成为 key window 以接收键盘事件（搜索框）
    override var canBecomeKey: Bool { true }
    // 不成为 main window，避免抢走原应用的 main 状态
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        hidePanel()
    }

    override func sendEvent(_ event: NSEvent) {
        // 搜索框始终持有焦点，方向键、回车和 Esc 在窗口层统一处理，
        // 避免被字段编辑器吞掉。输入法组字期间交给输入法处理。
        if event.type == .keyDown, !isComposingText, handleKeyDown(event) {
            return
        }
        super.sendEvent(event)
    }

    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return false }

        switch Int(event.keyCode) {
        case 125: // ↓
            viewModel.moveSelection(by: 1)
        case 126: // ↑
            viewModel.moveSelection(by: -1)
        case 36, 76: // Return / Enter
            viewModel.pasteSelectedItem()
        case 53: // Esc
            if viewModel.searchText.isEmpty {
                hidePanel()
            } else {
                viewModel.searchText = ""
            }
        default:
            return false
        }
        return true
    }
}

extension Notification.Name {
    static let clipboardPanelDidShow = Notification.Name("clipboardPanelDidShow")
}
