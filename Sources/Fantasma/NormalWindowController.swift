import AppKit

/// One normal, titled terminal window (R19): standard level, yabai tiles
/// it like any app (KTD17), hosts its own shell. Closing the window —
/// button, Cmd+W, or the shell exiting — ends that window's shell only.
@MainActor
final class NormalWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 900, height: 600)

    let window: NSWindow
    private let surface: TerminalSurface
    private var closed = false
    var onClosed: ((NormalWindowController) -> Void)?

    init(config: FantasmaConfig) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NormalWindowController.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "fantasma"
        window.isReleasedWhenClosed = false
        if !config.normalTitleBar {
            // Full-size content with a transparent, hidden title bar keeps
            // the traffic lights while the bar strip disappears (KTD17).
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        surface = TerminalSurface(frame: NSRect(origin: .zero, size: NormalWindowController.defaultSize), config: config)
        super.init()

        surface.onShellExit = { [weak self] in
            self?.close()
        }
        window.contentView = surface.terminalView
        window.delegate = self
    }

    func show() {
        // A normal window is a full app citizen: the regular policy brings
        // the menu bar (Fantasma -> Settings…, Cmd+,) while it is focused.
        NSApp.setActivationPolicy(.regular)
        surface.fitToSize()
        window.center()
        window.makeKeyAndOrderFront(nil)
        surface.focus()
    }

    /// Routes a font-zoom keypress (⌘=/⌘+/⌘−/⌘0) to this window's surface.
    func applyFontZoom(_ direction: FontZoom.Direction) {
        surface.applyFontZoom(direction)
    }

    /// Explicit close: tears the surface down (expected teardown — this
    /// window's shell ends but the app stays up) and notifies the owner.
    func close() {
        guard !closed else { return }
        closed = true
        surface.teardown()
        window.orderOut(nil)
        let finished = self
        onClosed?(finished)
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}
