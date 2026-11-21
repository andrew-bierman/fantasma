import AppKit
import GhosttyTheme

// CLI routing runs before any app state is touched: `+actions` print or
// post to the running instance and exit; anything else launches the app.
// `--new-window` and `--pin` remain as quiet aliases.
var arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--new-window") {
    arguments[index] = "+new-window"
}
// One-shot frame override for the next float summon:
//   fantasma +toggle-float --width 500 --height 320 --x 100 --y 80
var pendingFrame: [String: Int] = [:]
var pendingFrameFile: String?
for index in arguments.indices {
    let flag = arguments[index]
    let keys = ["--width", "--height", "--x", "--y"]
    if keys.contains(flag), index + 1 < arguments.count,
       let value = Int(arguments[index + 1]) {
        pendingFrame[String(flag.dropFirst())] = value
        pendingFrameFile = "/tmp/fantasma-pending-frame"
    }
}
if let file = pendingFrameFile {
    let line = pendingFrame.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";")
    try? line.write(toFile: file, atomically: true, encoding: .utf8)
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
