import AppKit
import GhosttyTheme

/// The binary doubles as a CLI (mirroring Ghostty's `+action` convention):
/// `fantasma +new-window`, `+toggle-float`, `+show-config`, `+list-themes`,
/// `+reload-config`. Actions are posted over DistributedNotificationCenter
/// to the running instance, or handled locally and printed when no instance
/// is needed.
enum FantasmaCLI {
    static let actions = ["+new-window", "+toggle-float", "+show-config", "+list-themes", "+reload-config"]

    /// Returns true when the arguments name a CLI action (caller should not
    /// continue into the app).
    static func handle(_ arguments: [String]) -> Bool {
        guard let action = arguments.first, actions.contains(action) else {
            return false
        }
        switch action {
        case "+new-window":
            post(.fantasmaNewWindow)
        case "+toggle-float":
            post(.fantasmaToggleFloat)
        case "+reload-config":
            post(.fantasmaReloadConfig)
        case "+show-config":
            printShowConfig()
        case "+list-themes":
            printThemes()
        default:
            break
        }
        return true
    }

    private static func post(_ name: Notification.Name) {
        // deliverImmediately is required: default posts are tied to the
        // poster's app context and get dropped by the fast-exiting CLI
        // process before notifyd delivers them.
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private static func printShowConfig() {
        let config = FantasmaConfigLoader.load()
        var lines = [
            "theme = \(config.theme)",
            "font_size = \(config.fontSize)",
            "padding = \(config.padding)",
            "clear_on_open = \(config.clearOnOpen)",
            "copy_on_select = \(config.copyOnSelect)",
            "normal_title_bar = \(config.normalTitleBar)",
            "link_url = \(config.linkUrl)",
            "remember_frame = \(config.rememberFrame)",
        ]
        if let family = config.fontFamily { lines.append("font_family = \(family)") }
        if let light = config.themeLight { lines.append("theme_light = \(light)") }
        if let dark = config.themeDark { lines.append("theme_dark = \(dark)") }
        if let width = config.floatWidth { lines.append("float_width = \(width)") }
        if let height = config.floatHeight { lines.append("float_height = \(height)") }
        if let x = config.floatX { lines.append("float_x = \(x)") }
        if let y = config.floatY { lines.append("float_y = \(y)") }
        if !config.hotkey.isEmpty { lines.append("hotkey = \(config.hotkey)") }
        print(lines.joined(separator: "\n"))
    }

    private static func printThemes() {
        for definition in GhosttyThemeCatalog.search("").sorted(by: { $0.name < $1.name }) {
            print(definition.name)
        }
    }
}
