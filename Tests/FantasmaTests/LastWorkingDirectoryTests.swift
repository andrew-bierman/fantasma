import XCTest
@testable import Fantasma

final class LastWorkingDirectoryTests: XCTestCase {
    /// Distinct identities without a real surface object. The sentinel
    /// objects are retained for the whole test: an unreferenced NSObject
    /// is freed immediately under ARC and the next allocation can land on
    /// the same address, which would alias two ObjectIdentifiers together.
    private var identityKeepers: [NSObject] = []
    private func freshID() -> ObjectIdentifier {
        let keeper = NSObject()
        identityKeepers.append(keeper)
        return ObjectIdentifier(keeper)
    }

    func testUnknownSurfaceSpawnsAtFallback() {
        let tracker = LastWorkingDirectory(fallback: "/Users/x")
        XCTAssertEqual(tracker.spawnDirectory(), "/Users/x")
        XCTAssertNil(tracker.current)
    }

    private var scratch: [String] = []

    override func tearDownWithError() throws {
        for path in scratch {
            try? FileManager.default.removeItem(atPath: path)
        }
        scratch.removeAll()
    }

    /// Creates a real temporary directory; `spawnDirectory` validates
    /// existence, so spawn-path assertions need live paths.
    private func makeDirectory(_ tag: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fantasma-lwd-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        scratch.append(url.path)
        return url.path
    }

    func testActivateThenRecordFeedsSpawnDirectory() throws {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.activate(surface)
        let directory = try makeDirectory("build")
        tracker.record(surface, directory: directory)
        XCTAssertEqual(tracker.current, directory)
        XCTAssertEqual(tracker.spawnDirectory(), directory)
    }

    func testRecordBeforeActivateStillSurfacesLater() {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.record(surface, directory: "/tmp/build")
        XCTAssertNil(tracker.current)
        tracker.activate(surface)
        XCTAssertEqual(tracker.current, "/tmp/build")
    }

    func testMostRecentlyActiveSurfaceWins() throws {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let float = freshID()
        let normal = freshID()
        let floatPath = try makeDirectory("float")
        let normalPath = try makeDirectory("normal")
        tracker.record(float, directory: floatPath)
        tracker.record(normal, directory: normalPath)
        tracker.activate(float)
        XCTAssertEqual(tracker.spawnDirectory(), floatPath)
        tracker.activate(normal)
        XCTAssertEqual(tracker.spawnDirectory(), normalPath)
    }

    func testLatestReportReplacesPrevious() {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.activate(surface)
        tracker.record(surface, directory: "/tmp/one")
        tracker.record(surface, directory: "/tmp/two")
        XCTAssertEqual(tracker.current, "/tmp/two")
    }

    func testNonPathReportsAreRejected() {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.activate(surface)
        // file:// URL, empty string, and bare "/" (the root is never a
        // useful cwd and would mask a parse failure).
        tracker.record(surface, directory: "file://Mac.local/Users/x")
        tracker.record(surface, directory: "")
        tracker.record(surface, directory: "/")
        XCTAssertNil(tracker.current)
        XCTAssertEqual(tracker.spawnDirectory(), "/Users/x")
    }

    func testRemoveDropsSurfaceAndClearsActivation() {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.record(surface, directory: "/tmp/build")
        tracker.activate(surface)
        tracker.remove(surface)
        XCTAssertNil(tracker.current)
        XCTAssertEqual(tracker.spawnDirectory(), "/Users/x")
    }

    func testRemoveKeepsOtherSurfaceActive() {
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let a = freshID()
        let b = freshID()
        tracker.record(a, directory: "/tmp/a")
        tracker.record(b, directory: "/tmp/b")
        tracker.activate(b)
        tracker.remove(a)
        XCTAssertEqual(tracker.current, "/tmp/b")
    }

    func testDeletedDirectoryFallsBack() throws {
        let doomed = FileManager.default.temporaryDirectory
            .appendingPathComponent("fantasma-lwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: doomed, withIntermediateDirectories: true)
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.record(surface, directory: doomed.path)
        tracker.activate(surface)
        XCTAssertEqual(tracker.spawnDirectory(), doomed.path)
        try FileManager.default.removeItem(at: doomed)
        XCTAssertEqual(tracker.spawnDirectory(), "/Users/x")
    }

    func testFileAtPathIsRejectedForSpawn() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("fantasma-lwd-file-\(UUID().uuidString)")
        try Data().write(to: file)
        var tracker = LastWorkingDirectory(fallback: "/Users/x")
        let surface = freshID()
        tracker.record(surface, directory: file.path)
        tracker.activate(surface)
        XCTAssertEqual(tracker.spawnDirectory(), "/Users/x")
        try FileManager.default.removeItem(at: file)
    }
}
