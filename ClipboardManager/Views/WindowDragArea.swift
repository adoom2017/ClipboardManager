import SwiftUI
import AppKit

/// 无边框面板的拖拽把手。只在显式放置的区域内移动窗口，
/// 不影响列表滚动条等控件的鼠标拖拽。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
