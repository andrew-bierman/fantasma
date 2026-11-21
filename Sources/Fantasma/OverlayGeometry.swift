import AppKit

enum OverlayGeometry {
    static let defaultSize = NSSize(width: 960, height: 620)
    static let minimumSize = NSSize(width: 320, height: 180)
    static let topInset: CGFloat = 110

    static func frame(for visibleFrame: NSRect) -> NSRect {
        let width = min(defaultSize.width, visibleFrame.width)
        let height = min(defaultSize.height, visibleFrame.height)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.maxY - topInset - height
        return NSRect(
            x: max(visibleFrame.minX, x),
            y: max(visibleFrame.minY, y),
            width: width,
            height: height
        )
    }
}
