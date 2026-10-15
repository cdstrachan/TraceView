import SwiftUI
import AppKit

struct HistogramResizeHandle: NSViewRepresentable {
    var onDragStart: () -> Void
    var onDrag: (CGFloat) -> Void
    var onDragEnd: () -> Void

    func makeNSView(context: Context) -> HistogramResizeNSView {
        let view = HistogramResizeNSView()
        view.onDragStart = onDragStart
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        return view
    }

    func updateNSView(_ nsView: HistogramResizeNSView, context: Context) {
        nsView.onDragStart = onDragStart
        nsView.onDrag = onDrag
        nsView.onDragEnd = onDragEnd
    }
}

final class HistogramResizeNSView: NSView {
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragStartY: CGFloat?

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartY = event.locationInWindow.y
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartY else { return }
        onDrag?(start - event.locationInWindow.y)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartY = nil
        onDragEnd?()
    }
}
