import AppKit
import GhosttyTerminal
import GhosttyTheme

@MainActor
final class TerminalSurface: NSObject {
    /// Theme construction hits the 485-entry catalog; memoize per name so
    /// repeated summons with clear-on-open don't re-scan it.
    private static var themeCache: [String: TerminalTheme] = [:]

    let terminalView: TerminalView
    private let controller: TerminalController
    /// Font zoom state for this surface (⌘=/⌘+/⌘−/⌘0); 0 is the config
    /// default the surface booted with.
    let fontZoom: FontZoom
    private(set) var shellHasExited = false
    /// Set before programmatic release so the close delegate does not route
    /// an expected teardown (clear-on-open dismissal, window close) to the
    /// quit path (KTD14 close-cause discipline).
    private(set) var isTearingDown = false
    /// Fired only on *spontaneous* shell death; expected teardowns never
    /// reach it.
    var onShellExit: (() -> Void)?

    /// The `link_url` gate, captured at surface creation like the other
    /// engine-side settings: false keeps links rendered (that lives in the
    /// engine) but the open path below drops every request.
    private let allowsLinkOpen: Bool
    /// Whether a pointing-hand cursor is currently pushed on the AppKit
    /// cursor stack; every push is paired with exactly one pop.
    private var hoverCursorPushed = false

    private static let termName = "xterm-256color"

    init(frame: NSRect, config: FantasmaConfig) {
        let theme = TerminalSurface.cachedTheme(named: TerminalSurface.effectiveThemeName(for: config))
        controller = TerminalController(
            configSource: .none,
            theme: theme,
            terminalConfiguration: TerminalConfiguration { builder in
                builder.withCursorStyle(.block)
                builder.withWindowPaddingX(config.padding)
                builder.withWindowPaddingY(config.padding)
                if let family = config.fontFamily {
                    builder.withFontFamily(family)
                }
                builder.withCustom("window-padding-balance", "true")
                builder.withCustom("scrollbar", "never")
                builder.withCustom("macos-option-as-alt", "true")
                builder.withCustom("scrollback-limit", "10000000")
                builder.withCustom("term", TerminalSurface.termName)
                builder.withCustom("clipboard-read", "deny")
                builder.withCustom("clipboard-write", "allow")
                builder.withCustom("clipboard-paste-protection", "false")
                builder.withCustom("copy-on-select", config.copyOnSelect ? "true" : "false")
            }
        )
        terminalView = TerminalView(frame: frame)
        fontZoom = FontZoom(defaultFontSize: config.fontSize)
        allowsLinkOpen = config.linkUrl
        super.init()

        terminalView.delegate = self
        terminalView.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: Float(config.fontSize),
            workingDirectory: NSHomeDirectory(),
            envVars: Self.surfaceEnvironment(),
            command: Self.loginShellCommand()
        )
        terminalView.controller = controller
    }

    func focus() {
        _ = terminalView.acquireProgrammaticFocus()
    }

    func fitToSize() {
        terminalView.fitToSize()
    }

    /// Routes a font-zoom keypress (⌘=/⌘+/⌘−/⌘0) to this surface's view.
    func applyFontZoom(_ direction: FontZoom.Direction) {
        fontZoom.apply(direction, on: terminalView)
    }

    /// Swaps the theme in place for system appearance changes; the live
    /// shell survives (the surface-rebuild path would kill it). No-ops when
    /// the controller already holds the theme.
    func applyTheme(named name: String) {
        controller.setTheme(TerminalSurface.cachedTheme(named: name))
    }

    /// Theme pair resolution for a config: `theme_light`/`theme_dark` win
    /// on their matching system appearance, everything else falls back to
    /// `theme` (ThemePair).
    static func effectiveThemeName(for config: FantasmaConfig) -> String {
        ThemePair.effectiveName(
            theme: config.theme,
            light: config.themeLight,
            dark: config.themeDark,
            isDarkAppearance: systemPrefersDarkAppearance()
        )
    }

    /// The app's effective interface appearance maps to the ThemePair side.
    /// Increased-contrast variants resolve to their base appearance.
    static func systemPrefersDarkAppearance() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func teardown() {
        guard !isTearingDown else { return }
        isTearingDown = true
        shellHasExited = true
        if hoverCursorPushed {
            NSCursor.pop()
            hoverCursorPushed = false
        }
        terminalView.controller = nil
    }

    /// Resolves a theme by catalog name. Upstream note: the catalog registry
    /// is empty at runtime in libghostty-spm 3.0.1, so the named lookup only
    /// works once upstream fixes it; Dracula (our default) resolves via its
    /// generated static directly.
    private static func resolvedTheme(named name: String) -> TerminalTheme {
        if let fromCatalog = GhosttyThemeCatalog.theme(named: name)?.toTerminalTheme() {
            return fromCatalog
        }
        switch name.lowercased() {
        case "dracula":
            return GhosttyThemeDefinition.dracula.toTerminalTheme()
        default:
            return .default
        }
    }

    /// Memoized resolvedTheme: theme construction scans the catalog, so
    /// repeated summons (and appearance swaps) reuse one build per name.
    private static func cachedTheme(named name: String) -> TerminalTheme {
        if let cached = themeCache[name] {
            return cached
        }
        let built = resolvedTheme(named: name)
        themeCache[name] = built
        return built
    }

    private static func loginShellCommand() -> String {
        let shell = loginShellPath()
        let quoted = "'" + shell.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "/bin/sh -c '\("exec \(quoted) -l")'"
    }

    /// The user's login shell path; shared with NormalWindowController so
    /// busy-state titles compare against the same shell this surface execs.
    static func loginShellPath() -> String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static func surfaceEnvironment() -> [String: String] {
        var environment = [
            "TERM": termName,
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "Fantasma",
        ]
        if let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !version.isEmpty {
            environment["TERM_PROGRAM_VERSION"] = version
        }
        if ProcessInfo.processInfo.environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment
    }
}

extension TerminalSurface: TerminalSurfaceCloseDelegate {
    func terminalDidClose(processAlive: Bool) {
        guard !isTearingDown, !shellHasExited else { return }
        shellHasExited = true
        onShellExit?()
    }
}

extension TerminalSurface: TerminalSurfaceBellDelegate {
    func terminalDidRingBell() {
        NSSound.beep()
        // Dock attention is only meaningful when the user is somewhere
        // else; bouncing while Fantasma is frontmost is just noise.
        guard !NSApp.isActive else { return }
        NSApp.requestUserAttention(.informationalRequest)
    }
}

extension TerminalSurface: TerminalSurfaceOpenURLDelegate {
    /// Schemes Fantasma will hand to the system opener. A terminal must
    /// never become a launcher for arbitrary URL schemes, so anything
    /// outside this allowlist is dropped silently. `file:` is deliberately
    /// absent: NSWorkspace.open on a file URL executes whatever LaunchServices
    /// handler claims that file type, which is exactly the launcher-shaped
    /// hole this gate exists to keep shut.
    private nonisolated static let openURLSchemes: Set<String> = ["http", "https", "mailto"]

    /// Parses and validates a link the engine surfaced for opening. Pure
    /// (no NSWorkspace, no state) so the allowlist is unit-testable. Network
    /// schemes must carry a host and `mailto:` an address — the engine's
    /// text scanner can surface degenerate URLs like bare `https://`, and
    /// opening one is pointless at best.
    nonisolated static func openableURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              Self.openURLSchemes.contains(scheme)
        else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = parsed.host, !host.isEmpty else { return nil }
        case "mailto":
            guard !parsed.path.isEmpty else { return nil }
        default:
            return nil
        }
        return parsed
    }

    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        // `kind` selects upstream styling (plain text vs OSC 8 vs HTML; the
        // wrapper maps every non-text/html kind to .unknown). Safety lives
        // in the scheme allowlist, so every kind flows through it alike.
        guard allowsLinkOpen, let parsed = Self.openableURL(from: url) else { return }
        NSWorkspace.shared.open(parsed)
    }
}

extension TerminalSurface: TerminalSurfaceHoverLinkDelegate {
    func terminalDidUpdateHoverLink(_ url: String?) {
        // The engine never touches NSCursor, so this pushed pointing hand
        // is the only cursor state Fantasma owns on the stack; hover end
        // (nil) and teardown each pop exactly once. With link_url off the
        // gate drops opens, so the affordance must not advertise them.
        if url != nil, allowsLinkOpen {
            if !hoverCursorPushed {
                NSCursor.pointingHand.push()
                hoverCursorPushed = true
            }
        } else if hoverCursorPushed {
            NSCursor.pop()
            hoverCursorPushed = false
        }
    }
}
