import XCTest
@testable import Fantasma

final class FantasmaConfigTests: XCTestCase {
    func testFullFileParsesAllKeys() {
        let text = """
        # fantasma config
        theme = GruvboxDark
        font_size = 15
        padding = 12
        clear_on_open = false
        """
        let config = FantasmaConfigLoader.parse(text)
        XCTAssertEqual(config.theme, "GruvboxDark")
        XCTAssertEqual(config.fontSize, 15)
        XCTAssertEqual(config.padding, 12)
        XCTAssertEqual(config.clearOnOpen, false)
    }

    func testMissingFileYieldsDefaults() {
        let config = FantasmaConfigLoader.load(path: "/tmp/does-not-exist-fantasma.conf")
        XCTAssertEqual(config, FantasmaConfig())
    }

    func testDefaultsMatchPlan() {
        let config = FantasmaConfig()
        XCTAssertEqual(config.theme, "Dracula")
        XCTAssertEqual(config.fontSize, 13)
        XCTAssertEqual(config.padding, 8)
        XCTAssertEqual(config.clearOnOpen, true)
    }

    func testUnknownKeysCommentsAndWhitespaceIgnored() {
        let text = """
        # comment
        unknown_key = whatever

          theme   =  SolarizedDark
        tabs = true
        """
        let config = FantasmaConfigLoader.parse(text)
        XCTAssertEqual(config.theme, "SolarizedDark")
        XCTAssertEqual(config.fontSize, 13)
        XCTAssertEqual(config.clearOnOpen, true)
    }

    func testClearOnOpenParsesCaseInsensitiveBooleans() {
        XCTAssertEqual(FantasmaConfigLoader.parse("clear_on_open = FALSE").clearOnOpen, false)
        XCTAssertEqual(FantasmaConfigLoader.parse("clear_on_open = True").clearOnOpen, true)
    }

    func testInvalidNumbersFallBackToDefaults() {
        let config = FantasmaConfigLoader.parse("font_size = big\npadding = -3\nfont_size = 0")
        XCTAssertEqual(config.fontSize, 13)   // non-numeric and zero fall back
        XCTAssertEqual(config.padding, 8)     // negative falls back
    }

    func testLoaderExpandsTildeAndReadsRealFile() throws {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("fantasma-test-\(UUID().uuidString).conf")
        try "theme = Nord".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(FantasmaConfigLoader.load(path: path).theme, "Nord")
    }
}
