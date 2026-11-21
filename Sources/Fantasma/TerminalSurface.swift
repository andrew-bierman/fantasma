import AppKit
import GhosttyTerminal
import GhosttyTheme

/// One login shell rendered by one long-lived libghostty surface (KTD1).
/// The view is the window's content; hiding the overlay never touches the
/// surface, so shell state survives hide/show cycles (KTD5).
@MainActor
final class TerminalSurface: NSObject {
    let terminalView: TerminalView
    private let controller: TerminalController
    private(set) var shellHasExited = false
    /// Fired once when the shell exits; the app quits (KTD9).
    var onShellExit: (() -> Void)?

    init(frame: NSRect) {
        let theme = GhosttyThemeCatalog.theme(named: "Dracula")?.toTerminalTheme() ?? .default
        controller = TerminalController(
            configSource: .none,
            theme: theme,
            terminalConfiguration: TerminalConfiguration { builder in
                builder.withCursorStyle(.block)
                builder.withWindowPaddingX(8)
                builder.withWindowPaddingY(8)
                builder.withCustom("window-padding-balance", "true")
                builder.withCustom("scrollbar", "never")
                builder.withCustom("macos-option-as-alt", "true")
                builder.withCustom("scrollback-limit", "10000000")
                builder.withCustom("term", "xterm-256color")
                // Deny programmatic clipboard reads until a real UI exists
                // to confirm them; user-initiated pastes stay allowed.
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
            workingDirectory: NSHomeDirectory(),
            envVars: Self.surfaceEnvironment(),
            command: Self.loginShellCommand()
        )
        terminalView.controller = controller
    }

    /// Makes the Ghostty surface the window's first responder so typing
    /// works (KTD4); the view's own focus path handles the mount race.
    func focus() {
        _ = terminalView.acquireProgrammaticFocus()
    }

    func fitToSize() {
        terminalView.fitToSize()
    }

    /// Wraps the user's login shell with `-l` — R9 requires a login shell,
    /// and the exec default does not guarantee one (justty precedent).
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
            "TERM": "xterm-256color",
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
        guard !shellHasExited else { return }
        shellHasExited = true
        onShellExit?()
    }
}
