import AppKit

// Explicit entry point: wire the delegate ourselves so
// applicationDidFinishLaunching fires reliably in a SwiftPM executable
// target (KTD7).
MainActor.assumeIsolated {
    let arguments = CommandLine.arguments

    if arguments.contains("--new-window") {
        DistributedNotificationCenter.default().post(
            name: .fantasmaNewWindow,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
        return
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
