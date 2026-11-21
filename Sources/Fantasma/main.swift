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
        pendingFrame[String(flag.dropFirst(2))] = value
        pendingFrameFile = "/tmp/fantasma-pending-frame"
    }
}
if let file = pendingFrameFile {
    // FloatFrameState.parse format (`key = value` lines): the app-side
    // consumer reuses that parser, so keep the formats identical.
    let order = ["width", "height", "x", "y"]
    let text = order.compactMap { key in
        pendingFrame[key].map { "\(key) = \($0)" }
    }.joined(separator: "\n")
    try? text.write(toFile: file, atomically: true, encoding: .utf8)
}
if FantasmaCLI.handle(Array(arguments.dropFirst())) {
    // deliverImmediately queues the post at notifyd before this returns;
    // a short settle still beats the old 250 ms on every scripted call.
    usleep(20_000)
    exit(0)
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
