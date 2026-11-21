import Carbon.HIToolbox

/// A parsed global hotkey: a Carbon virtual key code plus modifier flags,
/// the shape `RegisterEventHotKey` consumes.
struct HotkeyBinding: Equatable {
    let modifiers: UInt32
    let keyCode: UInt32
}

/// Result of parsing the `hotkey` config value.
enum HotkeyParseResult: Equatable {
    /// Empty or unset: the hotkey feature is off (the default).
    case disabled
    /// A usable binding.
    case hotkey(HotkeyBinding)
    /// Unparseable input; the raw value is carried so the caller can warn.
    case invalid(String)
}

/// Pure parser turning "cmd+grave"-style strings into Carbon key codes.
/// No I/O and no side effects, so it is directly unit-testable.
enum HotkeyParser {
    /// "cmd+grave", "ctrl+shift+space", "alt+e" → binding. Tokens are
    /// case-insensitive; modifiers are OR'd and at least one is required
    /// (a modifierless global key would swallow that keystroke in every
    /// app). Anything unrecognized yields `.invalid`.
    static func parse(_ raw: String) -> HotkeyParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .disabled }
        var modifiers: UInt32 = 0
        var tokens = trimmed.lowercased().split(separator: "+").map(String.init)
        guard let keyToken = tokens.popLast(), !keyToken.isEmpty else {
            return .invalid(trimmed)
        }
        for token in tokens {
            guard let flag = modifier(token) else { return .invalid(trimmed) }
            modifiers |= flag
        }
        guard modifiers != 0, let keyCode = keyCode(for: keyToken) else {
            return .invalid(trimmed)
        }
        return .hotkey(HotkeyBinding(modifiers: modifiers, keyCode: keyCode))
    }

    private static func modifier(_ token: String) -> UInt32? {
        switch token {
        case "cmd", "command": return UInt32(cmdKey)
        case "ctrl", "control": return UInt32(controlKey)
        case "alt", "opt", "option": return UInt32(optionKey)
        case "shift": return UInt32(shiftKey)
        default: return nil
        }
    }

    // ANSI virtual key codes follow the physical keyboard layout, not
    // ASCII order (e=0x0E, z=0x06, digits are scattered) — every key maps
    // through an explicit kVK constant.
    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A,
        "b": kVK_ANSI_B,
        "c": kVK_ANSI_C,
        "d": kVK_ANSI_D,
        "e": kVK_ANSI_E,
        "f": kVK_ANSI_F,
        "g": kVK_ANSI_G,
        "h": kVK_ANSI_H,
        "i": kVK_ANSI_I,
        "j": kVK_ANSI_J,
        "k": kVK_ANSI_K,
        "l": kVK_ANSI_L,
        "m": kVK_ANSI_M,
        "n": kVK_ANSI_N,
        "o": kVK_ANSI_O,
        "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q,
        "r": kVK_ANSI_R,
        "s": kVK_ANSI_S,
        "t": kVK_ANSI_T,
        "u": kVK_ANSI_U,
        "v": kVK_ANSI_V,
        "w": kVK_ANSI_W,
        "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0,
        "1": kVK_ANSI_1,
        "2": kVK_ANSI_2,
        "3": kVK_ANSI_3,
        "4": kVK_ANSI_4,
        "5": kVK_ANSI_5,
        "6": kVK_ANSI_6,
        "7": kVK_ANSI_7,
        "8": kVK_ANSI_8,
        "9": kVK_ANSI_9,
        "grave": kVK_ANSI_Grave,
        "escape": kVK_Escape,
        "tab": kVK_Tab,
        "space": kVK_Space,
        "minus": kVK_ANSI_Minus,
        "equal": kVK_ANSI_Equal,
        "comma": kVK_ANSI_Comma,
        "period": kVK_ANSI_Period,
    ]

    private static func keyCode(for token: String) -> UInt32? {
        keyCodes[token].map(UInt32.init)
    }
}
