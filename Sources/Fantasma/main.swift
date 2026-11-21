import AppKit

// Explicit entry point: wire the delegate ourselves so
// applicationDidFinishLaunching fires reliably in a SwiftPM executable
// target (KTD7).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
