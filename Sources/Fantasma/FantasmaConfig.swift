import Foundation

/// Resolved user configuration. Values merge from three layers, lowest to
/// highest: built-in defaults, the user's existing Ghostty config
/// (`~/.config/ghostty/config`, recognized keys only), and Fantasma's own
/// `~/.config/fantasma/fantasma.conf` (explicit overrides).
struct FantasmaConfig: Equatable {
    var theme = "Dracula"
    var fontSize = 13
    var padding = 8
    var clearOnOpen = true
    var copyOnSelect = true
    var fontFamily: String? = nil
    var floatWidth: Int? = nil
    var floatHeight: Int? = nil
    var floatX: Int? = nil
    var floatY: Int? = nil
    var normalTitleBar = true
    /// Raw `hotkey` binding string, e.g. "cmd+grave". Empty (the default)
    /// disables the global hotkey; the raw value is parsed at registration.
    var hotkey = ""
    var themeLight: String? = nil
    var themeDark: String? = nil
    var linkUrl = true
    /// When false, the float ignores the persisted frame state file on
    /// launch and skips writing it — placement comes from config/defaults.
    var rememberFrame = true
}

enum FantasmaConfigLoader {
    static let defaultPath = "~/.config/fantasma/fantasma.conf"
    static let ghosttyPath = "~/.config/ghostty/config"

    /// Expands the tilde-prefixed default path and creates the file with a
    /// commented template when absent, so Settings… always has a target.
    static func ensureDefaultFile() -> String {
        let resolved = (defaultPath as NSString).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: resolved) {
            try? FileManager.default.createDirectory(
                atPath: (resolved as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try? """
            # fantasma configuration
            # theme = Dracula          # any bundled catalog name
            # font_size = 13
            # padding = 8
            # clear_on_open = true     # false keeps the float's shell alive
            # copy_on_select = true
            # normal_title_bar = true  # false hides normal windows' title bar
            # float_width = 960
            # float_height = 620
            # float_x = 200            # omitted: centered horizontally
            # float_y = 110            # omitted: 110pt from the top
            # link_url = true          # false: links still render but cmd-click never opens
            # remember_frame = true    # false: float always places from config/defaults
            """.write(toFile: resolved, atomically: true, encoding: .utf8)
        }
        return resolved
    }

    static func load(path: String? = nil, ghosttyPath: String? = nil) -> FantasmaConfig {
        var values: [String: String] = [:]
        merge_ghostty(into: &values, path: ghosttyPath)
        merge_fantasma(into: &values, path: path)
        return resolve(values)
    }

    // MARK: - Layers

    private static func merge_fantasma(into values: inout [String: String], path: String?) {
        let resolved = ((path ?? defaultPath) as NSString).expandingTildeInPath
        if let text = try? String(contentsOfFile: resolved, encoding: .utf8) {
            mergeLines(text, into: &values)
        }
    }

    private static func merge_ghostty(into values: inout [String: String], path: String?) {
        let resolved = ((path ?? ghosttyPath) as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: resolved, encoding: .utf8) else { return }
        var ghosttyValues: [String: String] = [:]
        mergeLines(text, into: &ghosttyValues)
        // Map recognized Ghostty keys onto Fantasma's names; unrecognized
        // directives are dropped.
        let keyMap = [
            "theme": "theme",
            "font_size": "font_size",
            "window_padding_x": "padding",
            "window_padding_y": "padding",
            "copy_on_select": "copy_on_select",
            "font_family": "font_family",
        ]
        for (ghosttyKey, value) in ghosttyValues {
            if let fantasmaKey = keyMap[ghosttyKey] {
                values[fantasmaKey] = value
            }
        }
    }

    /// Parses `key = value` lines, skipping blanks and `#` comments. Ghostty
    /// directives that take no value or multi-token values we don't model
    /// still parse as strings; unknown keys are dropped at resolve time.
    private static func mergeLines(_ text: String, into values: inout [String: String]) {
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = keyNormalize(line[..<separator].trimmingCharacters(in: .whitespaces))
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            // Strip one layer of wrapping quotes (ghostty allows quoted values).
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
    }

    /// Fantasma keys are already snake_case; Ghostty keys are dash-case and
    /// may carry spaces in values. Normalizes both so a Ghostty `font-size`
    /// and a Fantasma `font_size` resolve identically.
    private static func keyNormalize(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    /// Exposed for tests: the ghostty→fantasma key normalization.
    static func parse_key(_ key: String) -> String {
        keyNormalize(key)
    }

    // MARK: - Resolution

    private static func resolve(_ values: [String: String]) -> FantasmaConfig {
        var config = FantasmaConfig()
        if let theme = values["theme"] { config.theme = theme }
        if let size = positiveInt(values["font_size"], minimum: 1) {
            config.fontSize = size
        }
        if let padding = nonNegativeInt(values["padding"]) {
            config.padding = padding
        }
        if let clear = bool(values["clear_on_open"]) {
            config.clearOnOpen = clear
        }
        if let copy = bool(values["copy_on_select"]) {
            config.copyOnSelect = copy
        }
        if let family = values["font_family"], !family.isEmpty {
            config.fontFamily = family
        }
        if let width = positiveInt(values["float_width"], minimum: 200) {
            config.floatWidth = width
        }
        if let height = positiveInt(values["float_height"], minimum: 150) {
            config.floatHeight = height
        }
        if let x = values["float_x"].flatMap(Int.init) { config.floatX = x }
        if let y = values["float_y"].flatMap(Int.init) { config.floatY = y }
        if let titleBar = bool(values["normal_title_bar"]) {
            config.normalTitleBar = titleBar
        }
        if let hotkey = values["hotkey"] {
            config.hotkey = hotkey
        }
        if let light = values["theme_light"], !light.isEmpty {
            config.themeLight = light
        }
        if let dark = values["theme_dark"], !dark.isEmpty {
            config.themeDark = dark
        }
        if let link = bool(values["link_url"]) {
            config.linkUrl = link
        }
        if let remember = bool(values["remember_frame"]) {
            config.rememberFrame = remember
        }
        return config
    }

    private static func bool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private static func positiveInt(_ value: String?, minimum: Int) -> Int? {
        guard let number = value.flatMap(Int.init), number >= minimum else { return nil }
        return number
    }

    private static func nonNegativeInt(_ value: String?) -> Int? {
        guard let number = value.flatMap(Int.init), number >= 0 else { return nil }
        return number
    }
}
