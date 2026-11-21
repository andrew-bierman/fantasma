import AppKit

// Explicit entry point: wire the delegate ourselves so
// applicationDidFinishLaunching fires reliably in a SwiftPM executable
// target (KTD7).
MainActor.assumeIsolated {
    let arguments = CommandLine.arguments

    // Windowed-mode trigger (KTD16): announce a new normal window to the
    // running instance and exit. With no instance running this posts to
    // nothing and exits quietly.
    if arguments.contains("--new-window") {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.andrewbierman.fantasma.new-window"),
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
