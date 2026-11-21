import AppKit
import GhosttyTerminal
import GhosttyTheme

@MainActor
final class TerminalSurface: NSObject {
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
        let theme = GhosttyThemeCatalog.theme(named: config.theme)?.toTerminalTheme() ?? .default
        controller = TerminalController(
            configSource: .none,
            theme: theme,
            terminalConfiguration: TerminalConfiguration { builder in
                builder.withCursorStyle(.block)
                builder.withWindowPaddingX(config.padding)
                builder.withWindowPaddingY(config.padding)
                builder.withCustom("window-padding-balance", "true")
                builder.withCustom("scrollbar", "never")
                builder.withCustom("macos-option-as-alt", "true")
                builder.withCustom("scrollback-limit", "10000000")
                builder.withCustom("term", TerminalSurface.termName)
                builder.withCustom("clipboard-read", "deny")
                builder.withCustom("clipboard-write", "allow")
                builder.withCustom("clipboard-paste-protection", "false")
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

    /// Tears the surface down explicitly: marks the teardown expected so the
    /// shell's death is not mistaken for a spontaneous exit, then releases
    /// the controller (ending the PTY and its shell).
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
        // Expected teardowns (clear-on-open dismissal, window close) are not
        // shell deaths; only a spontaneous exit reaches onShellExit.
        guard !isTearingDown, !shellHasExited else { return }
        shellHasExited = true
        onShellExit?()
    }
}
