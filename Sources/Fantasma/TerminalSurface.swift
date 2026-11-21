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
    private(set) var shellHasExited = false
    /// Set before programmatic release so the close delegate does not route
    /// an expected teardown (clear-on-open dismissal, window close) to the
    /// quit path (KTD14 close-cause discipline).
    private(set) var isTearingDown = false
    /// Fired only on *spontaneous* shell death; expected teardowns never
    /// reach it.
    var onShellExit: (() -> Void)?

    private static let termName = "xterm-256color"

    init(frame: NSRect, config: FantasmaConfig) {
        let theme: TerminalTheme
        if let cached = TerminalSurface.themeCache[config.theme] {
            theme = cached
        } else {
            let built = TerminalSurface.resolvedTheme(named: config.theme)
            TerminalSurface.themeCache[config.theme] = built
            theme = built
        }
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

    func teardown() {
        guard !isTearingDown else { return }
        isTearingDown = true
        shellHasExited = true
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
    /// never become a launcher for arbitrary URL schemes (file:, custom
    /// app schemes, …), so anything outside this allowlist is dropped
    /// silently.
    private static let openURLSchemes: Set<String> = ["http", "https", "mailto"]

    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              Self.openURLSchemes.contains(scheme)
        else { return }
        NSWorkspace.shared.open(parsed)
    }
}
