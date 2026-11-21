import AppKit
import GhosttyTheme

// CLI routing runs before any app state is touched: `+actions` print or
// post to the running instance and exit; anything else launches the app.
// `--new-window` and `--pin` remain as quiet aliases.
var arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--new-window") {
    arguments[index] = "+new-window"
}
if FantasmaCLI.handle(Array(arguments.dropFirst())) {
    // Let distributed posts flush before the process goes away.
    usleep(250_000)
    exit(0)
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
