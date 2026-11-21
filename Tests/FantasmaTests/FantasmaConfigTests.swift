import XCTest
@testable import Fantasma

final class FantasmaConfigTests: XCTestCase {
    private func writeTemp(_ text: String) -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("fantasma-test-\(UUID().uuidString).conf")
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testDefaultsMatchPlan() {
        XCTAssertEqual(FantasmaConfig(), FantasmaConfig(
            theme: "Dracula",
            fontSize: 13,
            padding: 8,
            clearOnOpen: true,
            copyOnSelect: true,
            fontFamily: nil,
            floatWidth: nil,
            floatHeight: nil,
            floatX: nil,
            floatY: nil,
            normalTitleBar: true,
            linkUrl: true
        ))
    }

    func testMissingFilesYieldDefaults() {
        XCTAssertEqual(
            FantasmaConfigLoader.load(path: "/tmp/does-not-exist-fantasma.conf"),
            FantasmaConfig()
        )
    }

    func testFantasmaKeysParse() {
        let path = writeTemp("""
        # fantasma config
        theme = GruvboxDark
        font_size = 15
        padding = 12
        clear_on_open = false
        float_width = 800
        float_height = 500
        float_x = 100
        float_y = 50
        normal_title_bar = false
        copy_on_select = false
        font_family = JetBrains Mono
        """)
        let config = FantasmaConfigLoader.load(path: path)
        XCTAssertEqual(config.theme, "GruvboxDark")
        XCTAssertEqual(config.fontSize, 15)
        XCTAssertEqual(config.padding, 12)
        XCTAssertEqual(config.clearOnOpen, false)
        XCTAssertEqual(config.copyOnSelect, false)
        XCTAssertEqual(config.fontFamily, "JetBrains Mono")
        XCTAssertEqual(config.floatWidth, 800)
        XCTAssertEqual(config.floatHeight, 500)
        XCTAssertEqual(config.floatX, 100)
        XCTAssertEqual(config.floatY, 50)
        XCTAssertEqual(config.normalTitleBar, false)
    }

    func testGhosttyKeysApplyWhenNoFantasmaOverrides() {
        let ghostty = writeTemp("""
        theme = Catppuccin Mocha
        font-size = 16
        window-padding-x = 10
        copy-on-select = false
        cursor-style = bar
        """)

        let config = FantasmaConfigLoader.load(
            path: "/tmp/does-not-exist-fantasma.conf",
            ghosttyPath: ghostty
        )
        XCTAssertEqual(config.theme, "Catppuccin Mocha")
        XCTAssertEqual(config.fontSize, 16)
        XCTAssertEqual(config.padding, 10)
        XCTAssertEqual(config.copyOnSelect, false)
    }

    func testFantasmaOverridesGhostty() {
        let ghostty = writeTemp("""
        theme = Catppuccin Mocha
        font-size = 16
        """)
        let fantasma = writeTemp("theme = Dracula")

        let config = FantasmaConfigLoader.load(path: fantasma, ghosttyPath: ghostty)
        XCTAssertEqual(config.theme, "Dracula")
        XCTAssertEqual(config.fontSize, 16)
    }

    func testRealDefaultPathLoadsAndRestoresUserFile() throws {
        // Regression: the tilde-prefixed default path must be expanded
        // before reading (a dropped expandingTildeInPath silently yields
        // defaults). Back up and restore any real user config around it.
        let dir = NSHomeDirectory() + "/.config/fantasma"
        let path = dir + "/fantasma.conf"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let backup = try? String(contentsOfFile: path, encoding: .utf8)
        try "float_width = 777".write(toFile: path, atomically: true, encoding: .utf8)
        defer {
            if let backup {
                try? backup.write(toFile: path, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        XCTAssertEqual(FantasmaConfigLoader.load().floatWidth, 777)
    }

    func testGhosttyDashKeysNormalizeToSnake() {
        XCTAssertEqual(FantasmaConfigLoader.parse_key("font-size"), "font_size")
        XCTAssertEqual(FantasmaConfigLoader.parse_key("WINDOW-PADDING-X"), "window_padding_x")
    }

    func testLinkUrlGateParses() {
        XCTAssertEqual(FantasmaConfig().linkUrl, true)
        let off = FantasmaConfigLoader.load(path: writeTemp("link_url = false"))
        XCTAssertEqual(off.linkUrl, false)
        // Ghostty's `link-url` is NOT mapped onto the gate: upstream it
        // switches URL detection/underline off entirely, while this gate
        // only decides whether a click opens. Different semantics, so the
        // recognized-keys map drops it on purpose.
        let ghosttyLinkOff = FantasmaConfigLoader.load(
            path: "/tmp/does-not-exist-fantasma.conf",
            ghosttyPath: writeTemp("link-url = NO")
        )
        XCTAssertEqual(ghosttyLinkOff.linkUrl, true)
        // Unparseable values keep the default rather than silently disabling.
        let garbage = FantasmaConfigLoader.load(path: writeTemp("link_url = sometimes"))
        XCTAssertEqual(garbage.linkUrl, true)
    }

    func testRememberFrameParses() {
        XCTAssertEqual(FantasmaConfig().rememberFrame, true)
        let off = FantasmaConfigLoader.load(path: writeTemp("remember_frame = false"))
        XCTAssertEqual(off.rememberFrame, false)
        let quoted = FantasmaConfigLoader.load(path: writeTemp("remember_frame = \"false\""))
        XCTAssertEqual(quoted.rememberFrame, false)
        let garbage = FantasmaConfigLoader.load(path: writeTemp("remember_frame = sometimes"))
        XCTAssertEqual(garbage.rememberFrame, true)
    }

    func testUnreadablePrimaryConfigSignals() throws {
        // An existing-but-unreadable primary config is a transient failure:
        // the loader reports it instead of silently applying defaults.
        let path = writeTemp("theme = Dracula")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: path
        )
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        let loaded = FantasmaConfigLoader.loadWithStatus(path: path)
        XCTAssertEqual(loaded.primaryReadable, false)
        // A MISSING primary file is legitimate "use defaults" — readable.
        let missing = FantasmaConfigLoader.loadWithStatus(path: "/tmp/does-not-exist-fantasma.conf")
        XCTAssertEqual(missing.primaryReadable, true)
        XCTAssertEqual(missing.config, FantasmaConfig())
    }

    func testUnknownKeysAndCommentsIgnored() {
        let path = writeTemp("""
        # comment
        unknown_directive = whatever
        cursor-style = bar

          theme   =  SolarizedDark
        """)
        let config = FantasmaConfigLoader.load(path: path)
        XCTAssertEqual(config.theme, "SolarizedDark")
        XCTAssertEqual(config.fontSize, 13)
    }

    func testBoolAndNumberValidation() {
        let path = writeTemp("""
        clear_on_open = FALSE
        copy_on_select = yes
        font_size = 0
        padding = -3
        float_width = 0
        """)
        let config = FantasmaConfigLoader.load(path: path)
        XCTAssertEqual(config.clearOnOpen, false)
        XCTAssertEqual(config.copyOnSelect, true)
        XCTAssertEqual(config.fontSize, 13)
        XCTAssertEqual(config.padding, 8)
        XCTAssertEqual(config.floatWidth, nil)
    }
}
