import AppKit

/// One normal, titled terminal window (R19): standard level, yabai tiles
/// it like any app (KTD17), hosts its own shell. Closing the window —
/// button, Cmd+W, or the shell exiting — ends that window's shell only.
@MainActor
final class NormalWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let surface: TerminalSurface
    private var closed = false
    var onClosed: ((NormalWindowController) -> Void)?

    init(config: FantasmaConfig) {
        let size = NSSize(width: 900, height: 600)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "fantasma"
        window.isReleasedWhenClosed = false
        surface = TerminalSurface(frame: NSRect(origin: .zero, size: size), config: config)
        super.init()

        surface.onShellExit = { [weak self] in
            self?.close()
        }
        window.contentView = surface.terminalView
        window.delegate = self
    }

    func show() {
        surface.fitToSize()
        window.center()
        window.makeKeyAndOrderFront(nil)
        surface.focus()
    }

    /// Explicit close: tears the surface down (expected teardown — this
    /// window's shell ends but the app stays up) and notifies the owner.
    func close() {
        guard !closed else { return }
        closed = true
        surface.teardown()
        window.orderOut(nil)
        onClosed?(self)
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}
