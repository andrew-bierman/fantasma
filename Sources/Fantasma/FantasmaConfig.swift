import Foundation

/// Resolved user configuration with plan defaults (R16): theme name,
/// font size, window padding, and whether dismissing the float discards
/// the shell (KD6: cleared by default).
struct FantasmaConfig: Equatable {
    var theme = "Dracula"
    var fontSize = 13
    var padding = 8
    var clearOnOpen = true
}

enum FantasmaConfigLoader {
    static let defaultPath = "~/.config/fantasma/fantasma.conf"

    static func load(path: String? = nil) -> FantasmaConfig {
        let resolved = path ?? (defaultPath as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: resolved, encoding: .utf8) else {
            return FantasmaConfig()
        }
        return parse(text)
    }

    static func parse(_ text: String) -> FantasmaConfig {
        var config = FantasmaConfig()
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "theme":
                config.theme = value
            case "font_size":
                if let size = Int(value), size >= 1 {
                    config.fontSize = size
                }
            case "padding":
                if let padding = Int(value), padding >= 0 {
                    config.padding = padding
                }
            case "clear_on_open":
                config.clearOnOpen = parseBool(value, fallback: config.clearOnOpen)
            default:
                continue
            }
        }
        return config
    }

    private static func parseBool(_ value: String, fallback: Bool) -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return fallback
        }
    }
}
