import AppKit

/// Placement math for the overlay frame (KTD10): configured size (or the
/// 960×620 default), centered horizontally with a fixed top inset, or at
/// explicitly configured coordinates — always inside the visible frame.
/// The minimum size floor governs interactive resizing (contentMinSize),
/// not placement.
enum OverlayGeometry {
    static let defaultSize = NSSize(width: 960, height: 620)
    static let minimumSize = NSSize(width: 320, height: 180)
    static let topInset: CGFloat = 110

    static func frame(for visibleFrame: NSRect) -> NSRect {
        frame(for: visibleFrame, config: FantasmaConfig())
    }

    static func frame(for visibleFrame: NSRect, config: FantasmaConfig) -> NSRect {
        let width = CGFloat(config.floatWidth ?? Int(defaultSize.width))
        let height = CGFloat(config.floatHeight ?? Int(defaultSize.height))
        let size = NSSize(
            width: min(width, visibleFrame.width),
            height: min(height, visibleFrame.height)
        )

        if let x = config.floatX, let y = config.floatY {
            let origin = NSPoint(
                x: visibleFrame.minX + CGFloat(x),
                y: visibleFrame.maxY - CGFloat(y) - size.height
            )
            return NSRect(origin: origin, size: size)
        }
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - topInset - height
        return NSRect(
            x: max(visibleFrame.minX, x),
            y: max(visibleFrame.minY, y),
            width: size.width,
            height: size.height
        )
    }
}
