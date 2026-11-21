import XCTest
@testable import Fantasma

final class OverlayGeometryTests: XCTestCase {
    func testDefaultFrameCentersHorizontallyWithTopInset() {
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = OverlayGeometry.frame(for: visible)
        XCTAssertEqual(frame.width, 960)
        XCTAssertEqual(frame.height, 620)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, visible.maxY - OverlayGeometry.topInset, accuracy: 0.5)
    }

    func testFrameFitsVisibleFrameBetweenMinimumAndDefault() {
        // Visible frame larger than the minimum but smaller than the default:
        // the window fills what fits rather than overhanging.
        let visible = NSRect(x: 0, y: 0, width: 400, height: 240)
        let frame = OverlayGeometry.frame(for: visible)
        XCTAssertEqual(frame.width, 400)
        XCTAssertEqual(frame.height, 240)
    }

    func testScreenSmallerThanMinimumStaysOnScreen() {
        // A screen smaller than the minimum cannot host the floor size;
        // staying fully on-screen wins over the floor (the floor governs
        // user resizing, which cannot shrink below the screen anyway).
        let visible = NSRect(x: 0, y: 0, width: 200, height: 150)
        let frame = OverlayGeometry.frame(for: visible)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    func testFrameStaysInsideVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 340, height: 200)
        let frame = OverlayGeometry.frame(for: visible)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    func testFrameOnShortVisibleFrameClampsToWhatFits() {
        // Visible frame taller than the minimum but shorter than the default:
        // the window fits the available height instead of overhanging.
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 500)
        let frame = OverlayGeometry.frame(for: visible)
        XCTAssertEqual(frame.height, 500)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
    }

    func testEdgeDetectionAllFourSidesAndCorners() {
        let bounds = NSRect(x: 0, y: 0, width: 960, height: 620)
        XCTAssertEqual(EdgeResizeControllerView.edges(at: NSPoint(x: 2, y: 310), in: bounds), [.left])
        XCTAssertEqual(EdgeResizeControllerView.edges(at: NSPoint(x: 957, y: 310), in: bounds), [.right])
        XCTAssertEqual(EdgeResizeControllerView.edges(at: NSPoint(x: 480, y: 618), in: bounds), [.top])
        XCTAssertEqual(EdgeResizeControllerView.edges(at: NSPoint(x: 480, y: 2), in: bounds), [.bottom])
        XCTAssertEqual(
            EdgeResizeControllerView.edges(at: NSPoint(x: 1, y: 619), in: bounds),
            [.left, .top]
        )
        XCTAssertEqual(
            EdgeResizeControllerView.edges(at: NSPoint(x: 480, y: 310), in: bounds),
            []
        )
    }

    func testWindowResizeClampsToLeftEdgeDrag() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Drag the left edge far past the minimum: the right edge stays
        // anchored and the width clamps to the floor.
        window.resize(
            from: NSRect(x: 100, y: 100, width: 960, height: 620),
            delta: NSPoint(x: 700, y: 0),
            edges: [.left],
            minSize: OverlayGeometry.minimumSize
        )
        XCTAssertEqual(window.frame.width, OverlayGeometry.minimumSize.width)
        XCTAssertEqual(window.frame.maxX, 100 + 960, accuracy: 0.5)
    }

    func testWindowResizeTopEdgeAnchorsBottom() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.resize(
            from: NSRect(x: 100, y: 100, width: 960, height: 620),
            delta: NSPoint(x: 0, y: -120),
            edges: [.top],
            minSize: OverlayGeometry.minimumSize
        )
        XCTAssertEqual(window.frame.height, 740)
        XCTAssertEqual(window.frame.maxY, 100 + 620, accuracy: 0.5)
    }
}
