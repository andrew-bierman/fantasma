import XCTest
@testable import Fantasma

final class ThemePairTests: XCTestCase {
    // MARK: - Resolver rules

    func testUnsetPairFallsBackToThemeForBothAppearances() {
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: nil, dark: nil, isDarkAppearance: false),
            "Dracula"
        )
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: nil, dark: nil, isDarkAppearance: true),
            "Dracula"
        )
    }

    func testDarkSideWinsOnDarkAppearance() {
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: "Solarized Light", dark: "Solarized Dark", isDarkAppearance: true),
            "Solarized Dark"
        )
    }

    func testLightSideWinsOnLightAppearance() {
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: "Solarized Light", dark: "Solarized Dark", isDarkAppearance: false),
            "Solarized Light"
        )
    }

    func testOnlyLightSetCoversLightAndFallsBackOnDark() {
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: "Solarized Light", dark: nil, isDarkAppearance: false),
            "Solarized Light"
        )
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: "Solarized Light", dark: nil, isDarkAppearance: true),
            "Dracula"
        )
    }

    func testOnlyDarkSetCoversDarkAndFallsBackOnLight() {
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: nil, dark: "Solarized Dark", isDarkAppearance: true),
            "Solarized Dark"
        )
        XCTAssertEqual(
            ThemePair.effectiveName(theme: "Dracula", light: nil, dark: "Solarized Dark", isDarkAppearance: false),
            "Dracula"
        )
    }

    // MARK: - Config keys

    func testPairKeysParse() {
        let path = Self.writeTemp("""
        theme = Dracula
        theme_light = Solarized Light
        theme_dark = Solarized Dark
        """)
        let config = FantasmaConfigLoader.load(path: path)
        XCTAssertEqual(config.theme, "Dracula")
        XCTAssertEqual(config.themeLight, "Solarized Light")
        XCTAssertEqual(config.themeDark, "Solarized Dark")
    }

    func testPairKeysDefaultToNil() {
        XCTAssertNil(FantasmaConfig().themeLight)
        XCTAssertNil(FantasmaConfig().themeDark)
    }

    func testEmptyPairValuesAreDropped() {
        let path = Self.writeTemp("""
        theme = Dracula
        theme_light = ""
        theme_dark =
        """)
        let config = FantasmaConfigLoader.load(path: path)
        XCTAssertNil(config.themeLight)
        XCTAssertNil(config.themeDark)
    }

    func testGhosttyDashCasePairKeysNormalize() {
        // keyNormalize is applied to every parsed key, so dash-case
        // spellings land on the same fields.
        let path = Self.writeTemp("""
        theme-light = Solarized Light
        theme-dark = Solarized Dark
        """)
        let config = FantasmaConfigLoader.load(path: path)
        XCTAssertEqual(config.themeLight, "Solarized Light")
        XCTAssertEqual(config.themeDark, "Solarized Dark")
    }

    private static func writeTemp(_ text: String) -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("fantasma-test-\(UUID().uuidString).conf")
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
