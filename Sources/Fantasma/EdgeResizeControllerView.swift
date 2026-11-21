import AppKit

/// Supplies edge resizing for a borderless window: `.resizable` in the
/// styleMask alone gives no edge affordance without a title bar (KTD11).
/// The view covers the whole content area but is transparent to the
/// interior — `hitTest` returns self only inside the edge zones, so clicks
/// meant for the content pass through untouched.
final class EdgeResizeControllerView: NSView {
    private static let thickness: CGFloat = 5

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let edges = Self.edges(at: local, in: bounds)
        return edges.isEmpty ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        let local = convert(start, from: nil)
        let edges = Self.edges(at: local, in: bounds)
        guard !edges.isEmpty else { return }
        let startFrame = window.frame
        var dragging = true
        while dragging, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                dragging = false
                continue
            }
            let delta = NSPoint(
                x: next.locationInWindow.x - start.x,
                y: next.locationInWindow.y - start.y
            )
            window.resize(from: startFrame, delta: delta, edges: edges, minSize: OverlayGeometry.minimumSize)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    static func edges(at local: NSPoint, in bounds: NSRect) -> Edges {
        var edges: Edges = []
        if local.x <= thickness { edges.insert(.left) }
        if local.x >= bounds.maxX - thickness { edges.insert(.right) }
        if local.y <= thickness { edges.insert(.bottom) }
        if local.y >= bounds.maxY - thickness { edges.insert(.top) }
        return edges
    }
}

extension NSWindow {
    /// Applies a drag delta to the start frame for the given edges, keeping
    /// the opposite edge anchored and clamping to the minimum size.
    func resize(from startFrame: NSRect, delta: NSPoint, edges: EdgeResizeControllerView.Edges, minSize: NSSize) {
        var frame = startFrame
        var minX = startFrame.minX, minY = startFrame.minY
        var width = startFrame.width, height = startFrame.height

        if edges.contains(.left) {
            minX = startFrame.minX + delta.x
            width = startFrame.maxX - minX
            if width < minSize.width {
                width = minSize.width
                minX = startFrame.maxX - minSize.width
            }
        } else if edges.contains(.right) {
            width = max(minSize.width, startFrame.width + delta.x)
        }

        if edges.contains(.bottom) {
            minY = startFrame.minY + delta.y
            height = startFrame.maxY - minY
            if height < minSize.height {
                height = minSize.height
                minY = startFrame.maxY - minSize.height
            }
        } else if edges.contains(.top) {
            height = max(minSize.height, startFrame.height - delta.y)
            minY = startFrame.maxY - height
        }

        setFrame(NSRect(x: minX, y: minY, width: width, height: height), display: true)
    }
}
