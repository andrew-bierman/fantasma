import AppKit
import GhosttyTerminal
import GhosttyTheme

/// The binary doubles as a CLI (mirroring Ghostty's `+action` convention):
/// `fantasma +new-window`, `+toggle-float`, `+show-config`, `+list-themes`,
/// `+reload-config`. Actions are posted over DistributedNotificationCenter
/// to the running instance, or handled locally and printed when no instance
/// is needed.
enum FantasmaCLI {
    static let actions = ["+new-window", "+toggle-float", "+show-config", "+list-themes", "+reload-config", "+verify-bundle"]

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
        case "+verify-bundle":
            MainActor.assumeIsolated { verifyBundle() }
        default:
            break
        }
        return true
    }

    @MainActor
    private static func verifyBundle() {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app", let resources = bundle.resourceURL else {
            failBundleCheck("Run this check from the executable inside Fantasma.app.")
        }

        // Exercise the same Ghostty initialization as the first terminal window.
        _ = TerminalController(configSource: .none)
        let resourcePath = resources.resolvingSymlinksInPath().path + "/"
        for directory in [GhosttyRuntimeResources.directoryURL, GhosttyRuntimeResources.terminfoDirectoryURL] {
            guard let directory, directory.resolvingSymlinksInPath().path.hasPrefix(resourcePath) else {
                failBundleCheck("Ghostty resources must resolve inside the app bundle.")
            }
        }
        print("Ghostty initialized using packaged resources.")
    }

    private static func failBundleCheck(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
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
            "menu_bar_icon = \(config.menuBarIcon)",
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
