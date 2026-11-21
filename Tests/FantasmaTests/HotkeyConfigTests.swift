import XCTest
import Carbon.HIToolbox
@testable import Fantasma

final class HotkeyConfigTests: XCTestCase {
    private func parse(_ raw: String) -> HotkeyParseResult {
        HotkeyParser.parse(raw)
    }

    private func changed(_ previous: String, _ current: String) -> Bool {
        HotkeyParser.changed(previous: previous, current: current)
    }

    func testChangedIsFalseWhenBindingUnchanged() {
        // Equal non-empty bindings: an unrelated config reload must not
        // unregister/re-register the hotkey (R3).
        XCTAssertFalse(changed("cmd+grave", "cmd+grave"))
        // Two empties: still disabled, still no work (R3).
        XCTAssertFalse(changed("", ""))
    }

    func testChangedIsTrueWhenBindingChanges() {
        // Enable from off (R1).
        XCTAssertTrue(changed("", "cmd+grave"))
        // Disable to off (R2).
        XCTAssertTrue(changed("cmd+grave", ""))
        // Rebind between two live combos (R1).
        XCTAssertTrue(changed("cmd+grave", "ctrl+space"))
    }

    func testEmptyAndWhitespaceAreDisabled() {
        XCTAssertEqual(parse(""), .disabled)
        XCTAssertEqual(parse("   "), .disabled)
    }

    func testCmdGraveParses() {
        XCTAssertEqual(
            parse("cmd+grave"),
            .hotkey(HotkeyBinding(modifiers: UInt32(cmdKey), keyCode: UInt32(kVK_ANSI_Grave)))
        )
    }

    func testCtrlShiftSpaceParses() {
        XCTAssertEqual(
            parse("ctrl+shift+space"),
            .hotkey(HotkeyBinding(
                modifiers: UInt32(controlKey | shiftKey),
                keyCode: UInt32(kVK_Space)
            ))
        )
    }

    func testAltOptOptionAreAliases() {
        XCTAssertEqual(parse("alt+e"), parse("opt+e"))
        XCTAssertEqual(parse("alt+e"), parse("option+e"))
        XCTAssertEqual(parse("alt+e"), parse("ALT+E"))
        XCTAssertEqual(
            parse("alt+e"),
            .hotkey(HotkeyBinding(modifiers: UInt32(optionKey), keyCode: UInt32(kVK_ANSI_E)))
        )
    }

    func testNamedKeysParse() {
        let expected: [String: Int] = [
            "grave": kVK_ANSI_Grave,
            "escape": kVK_Escape,
            "tab": kVK_Tab,
            "space": kVK_Space,
            "minus": kVK_ANSI_Minus,
            "equal": kVK_ANSI_Equal,
            "comma": kVK_ANSI_Comma,
            "period": kVK_ANSI_Period,
        ]
        for (name, code) in expected {
            XCTAssertEqual(
                parse("cmd+\(name)"),
                .hotkey(HotkeyBinding(modifiers: UInt32(cmdKey), keyCode: UInt32(code))),
                name
            )
        }
    }

    func testLettersAndDigitsParse() {
        // Full a–z / 0–9 coverage: ANSI virtual key codes follow the
        // physical layout (not ASCII order), so every entry is asserted
        // against its own kVK constant.
        let expected: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ]
        for (key, code) in expected {
            XCTAssertEqual(
                parse("shift+\(key)"),
                .hotkey(HotkeyBinding(modifiers: UInt32(shiftKey), keyCode: UInt32(code))),
                key
            )
        }
    }

    func testInvalidInputCarriesRawValue() {
        XCTAssertEqual(parse("hyper+e"), .invalid("hyper+e"))
        XCTAssertEqual(parse("cmd+f13"), .invalid("cmd+f13"))
        XCTAssertEqual(parse("cmd+e+more"), .invalid("cmd+e+more"))
    }

    func testBareKeyWithoutModifierIsInvalid() {
        // A modifierless global key would swallow that keystroke in
        // every app.
        XCTAssertEqual(parse("e"), .invalid("e"))
        XCTAssertEqual(parse("cmd+"), .invalid("cmd+"))
    }

    func testConfigDefaultIsDisabled() {
        XCTAssertEqual(FantasmaConfig().hotkey, "")
    }

    func testConfigLoadsHotkeyValue() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("fantasma-hotkey-test-\(UUID().uuidString).conf")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try "hotkey = ctrl+grave".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(FantasmaConfigLoader.load(path: path).hotkey, "ctrl+grave")

        // Invalid values load as the raw string; the app layer decides —
        // the parser reports .invalid and registration stays off.
        try "hotkey = hyper+q".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(
            HotkeyParser.parse(FantasmaConfigLoader.load(path: path).hotkey),
            .invalid("hyper+q")
        )
    }
}
