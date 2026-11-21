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
            let built = GhosttyThemeCatalog.theme(named: config.theme)?.toTerminalTheme() ?? .default
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

    private static func loginShellCommand() -> String {
        let shell = loginShellPath()
        let quoted = "'" + shell.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "/bin/sh -c '\("exec \(quoted) -l")'"
    }

    private static func loginShellPath() -> String {
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
