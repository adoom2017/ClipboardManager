import SwiftUI
import AppKit

class FloatingPanelController: NSPanel {
    static let shared = FloatingPanelController()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 450),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.transient, .ignoresCycle]
        self.animationBehavior = .utilityWindow
        self.backgroundColor = .clear
        // 允许面板在非活跃应用时也接收鼠标事件
        self.hidesOnDeactivate = false
        // 不设置 becomesKeyOnlyIfNeeded，确保点击任何区域都能立即响应

        let viewModel = ClipboardListViewModel()
        let hostingView = NSHostingView(rootView: MenuBarView(clipboardListViewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // 用普通 NSView 做容器，避免 NSHostingView 直接作为 contentView
        // 时 AppKit 与 SwiftUI 布局系统互相触发 layoutSubtreeIfNeeded 的递归问题
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 450))
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.contentView = container
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        // 居中显示
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        // 显示面板并立即成为 key window，使列表点击第一下即可响应
        // NSPanel 的 .nonactivatingPanel 保证不会激活（切换）当前前台应用
        orderFrontRegardless()
        makeKey()
    }

    func hidePanel() {
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
}