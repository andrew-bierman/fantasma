import AppKit

/// Pure placement math for the overlay frame (KTD10): default size centered
/// horizontally in the visible frame, fixed inset from the top, never
/// smaller than the minimum size, never outside the visible frame.
enum OverlayGeometry {
    static let defaultSize = NSSize(width: 960, height: 620)
    static let minimumSize = NSSize(width: 320, height: 180)
    static let topInset: CGFloat = 110

    static func frame(for visibleFrame: NSRect) -> NSRect {
        let width = min(defaultSize.width, max(visibleFrame.width, minimumSize.width))
        let height = min(defaultSize.height, max(visibleFrame.height, minimumSize.height))
        let x = visibleFrame.midX - width / 2
        let y = min(
            visibleFrame.maxY - topInset - height,
            visibleFrame.maxY - height
        )
        return NSRect(
            x: max(visibleFrame.minX, x),
            y: max(visibleFrame.minY, y),
            width: width,
            height: height
        )
    }
}
