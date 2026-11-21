import XCTest
@testable import Fantasma

final class FloatFrameStateTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("fantasma-frame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Round-trip

    func testSerializedRoundTrip() {
        let state = FloatFrameState(x: 120, y: 90, width: 960, height: 620)
        XCTAssertEqual(FloatFrameState.parse(state.serialized()), state)
    }

    func testPartialStateRoundTrips() {
        let state = FloatFrameState(width: 480)
        XCTAssertEqual(FloatFrameState.parse(state.serialized()), state)
    }

    func testEmptyStateSerializesToCommentOnly() {
        XCTAssertEqual(FloatFrameState.parse(FloatFrameState().serialized()), FloatFrameState())
    }

    // MARK: - Corrupt-file fallback

    func testCorruptTextYieldsEmptyState() {
        let garbage = """
        this is not a state file
        x = not a number
        ===
        width = 12.5
        randomnoise
        """
        XCTAssertEqual(FloatFrameState.parse(garbage), FloatFrameState())
    }

    func testCorruptFileKeepsUsableLines() {
        // Corruption degrades line-by-line, not file-wide.
        let mixed = "x = 50\nbroken line\nheight = 300\n# comment\n"
        XCTAssertEqual(
            FloatFrameState.parse(mixed),
            FloatFrameState(x: 50, height: 300)
        )
    }

    func testLoadMissingFileReturnsNil() {
        let path = scratch.appendingPathComponent("absent.toml").path
        XCTAssertNil(FloatFrameState.load(path: path))
    }

    func testLoadAndStoreRoundTripOnDisk() throws {
        let path = scratch.appendingPathComponent("state.toml").path
        let state = FloatFrameState(x: 8, y: 12, width: 500, height: 333)
        try state.store(path: path)
        XCTAssertEqual(FloatFrameState.load(path: path), state)
    }

    func testStoreCreatesMissingDirectory() throws {
        let path = scratch.appendingPathComponent("nested/deeper/state.toml").path
        try FloatFrameState(x: 1, y: 2, width: 3, height: 4).store(path: path)
        XCTAssertEqual(
            FloatFrameState.load(path: path),
            FloatFrameState(x: 1, y: 2, width: 3, height: 4)
        )
    }

    // MARK: - Capture from a live frame

    func testFromFrameUsesConfigConvention() {
        // x from the left edge, y from the top edge of the visible frame.
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = NSRect(x: 100, y: 400, width: 560, height: 360)
        let state = FloatFrameState.from(frame: frame, visibleFrame: visible)
        XCTAssertEqual(state.x, 100)
        XCTAssertEqual(state.y, 1117 - 760) // top edge at y=760 in screen coords
        XCTAssertEqual(state.width, 560)
        XCTAssertEqual(state.height, 360)
    }

    func testFromFrameRespectsVisibleFrameOffset() {
        // A visible frame not at the origin (menu bar, dock) offsets both
        // measurements.
        let visible = NSRect(x: 40, y: 30, width: 800, height: 600)
        let frame = NSRect(x: 140, y: 130, width: 300, height: 200)
        let state = FloatFrameState.from(frame: frame, visibleFrame: visible)
        XCTAssertEqual(state.x, 100)
        XCTAssertEqual(state.y, 600 - 300)
    }

    func testCaptureThenPlaceRoundTripsThroughGeometry() {
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = OverlayGeometry.frame(for: visible)
        let state = FloatFrameState.from(frame: frame, visibleFrame: visible)
        let placed = OverlayGeometry.frame(
            for: visible,
            config: FloatFrameState.merged(into: FantasmaConfig(), state: state, visibleFrame: visible)
        )
        XCTAssertEqual(placed.width, frame.width)
        XCTAssertEqual(placed.height, frame.height)
        XCTAssertEqual(placed.minX, frame.minX, accuracy: 1)
        XCTAssertEqual(placed.maxY, frame.maxY, accuracy: 1)
    }

    // MARK: - Precedence (config wins over state wins over defaults)

    func testMergedStateWinsOverDefaults() {
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let merged = FloatFrameState.merged(
            into: FantasmaConfig(),
            state: FloatFrameState(x: 20, y: 40, width: 700, height: 500),
            visibleFrame: visible
        )
        XCTAssertEqual(merged.floatWidth, 700)
        XCTAssertEqual(merged.floatHeight, 500)
        XCTAssertEqual(merged.floatX, 20)
        XCTAssertEqual(merged.floatY, 40)
    }

    func testMergedConfigWinsOverState() {
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        var config = FantasmaConfig()
        config.floatWidth = 800
        config.floatX = 10
        let merged = FloatFrameState.merged(
            into: config,
            state: FloatFrameState(x: 999, y: 40, width: 700, height: 500),
            visibleFrame: visible
        )
        XCTAssertEqual(merged.floatWidth, 800) // config, not state's 700
        XCTAssertEqual(merged.floatX, 10) // config, not state's 999
        XCTAssertEqual(merged.floatHeight, 500) // state fills config's nil
        XCTAssertEqual(merged.floatY, 40)
    }

    func testMergedWithoutStatePassesConfigThrough() {
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let merged = FloatFrameState.merged(
            into: FantasmaConfig(),
            state: nil,
            visibleFrame: visible
        )
        XCTAssertNil(merged.floatWidth)
        XCTAssertNil(merged.floatHeight)
        XCTAssertNil(merged.floatX)
        XCTAssertNil(merged.floatY)
    }

    // MARK: - Clamp path

    func testStateClampedIntoVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let merged = FloatFrameState.merged(
            into: FantasmaConfig(),
            state: FloatFrameState(x: 10_000, y: -500, width: 500, height: 300),
            visibleFrame: visible
        )
        XCTAssertEqual(merged.floatX, 1200 - 500) // keeps the right edge on-screen
        XCTAssertEqual(merged.floatY, 0) // negative pulls up past the top
    }

    func testStateSizeClampedToVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 500)
        let merged = FloatFrameState.merged(
            into: FantasmaConfig(),
            state: FloatFrameState(x: 0, y: 0, width: 5000, height: 5000),
            visibleFrame: visible
        )
        XCTAssertEqual(merged.floatWidth, 1000)
        XCTAssertEqual(merged.floatHeight, 500)
    }

    func testStateSizeFlooredAtMinimum() {
        let visible = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let merged = FloatFrameState.merged(
            into: FantasmaConfig(),
            state: FloatFrameState(x: 5, y: 5, width: 50, height: 50),
            visibleFrame: visible
        )
        XCTAssertEqual(merged.floatWidth, Int(OverlayGeometry.minimumSize.width))
        XCTAssertEqual(merged.floatHeight, Int(OverlayGeometry.minimumSize.height))
    }

    func testClampedStatePlacesFullyOnScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let merged = FloatFrameState.merged(
            into: FantasmaConfig(),
            state: FloatFrameState(x: 10_000, y: -500, width: 500, height: 300),
            visibleFrame: visible
        )
        let frame = OverlayGeometry.frame(for: visible, config: merged)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    func testConfiguredXYStillBypassesStateClamp() {
        // Config x/y are OverlayGeometry's business (unchanged behaviour);
        // the clamp applies to state-derived values only.
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        var config = FantasmaConfig()
        config.floatX = 10_000
        config.floatY = 10_000
        let merged = FloatFrameState.merged(
            into: config,
            state: FloatFrameState(x: 0, y: 0),
            visibleFrame: visible
        )
        XCTAssertEqual(merged.floatX, 10_000)
        XCTAssertEqual(merged.floatY, 10_000)
    }
}
