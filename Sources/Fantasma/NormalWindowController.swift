import AppKit

/// One normal, titled terminal window (R19): standard level, yabai tiles
/// it like any app (KTD17), hosts its own shell. Closing the window —
/// button, Cmd+W, or the shell exiting — ends that window's shell only.
@MainActor
final class NormalWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 900, height: 600)

    let window: NSWindow
    private let surface: TerminalSurface
    private let shellName: String
    /// Login shell pid once observed at the pty's foreground (BusyTitle).
    private var shellPid: pid_t?
    /// Polls the surface's foreground pid so the title tracks the running
    /// command; invalidated in close() so no timer outlives the window.
    private var titlePollTimer: Timer?
    private var closed = false
    var onClosed: ((NormalWindowController) -> Void)?

    init(config: FantasmaConfig) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NormalWindowController.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = BusyTitle.idleTitle
        window.isReleasedWhenClosed = false
        if !config.normalTitleBar {
            // Full-size content with a transparent, hidden title bar keeps
            // the traffic lights while the bar strip disappears (KTD17).
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        surface = TerminalSurface(frame: NSRect(origin: .zero, size: NormalWindowController.defaultSize), config: config)
        shellName = (TerminalSurface.loginShellPath() as NSString).lastPathComponent
        super.init()

        surface.onShellExit = { [weak self] in
            self?.close()
        }
        window.contentView = surface.terminalView
        window.delegate = self
        startTitlePolling()
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

    /// Applies a theme to this window's surface in place; a system
    /// appearance switch must not kill the window's live shell.
    func applyTheme(named name: String) {
        surface.applyTheme(named: name)
    }

    /// Explicit close: tears the surface down (expected teardown — this
    /// window's shell ends but the app stays up) and notifies the owner.
    func close() {
        guard !closed else { return }
        closed = true
        stopTitlePolling()
        surface.teardown()
        window.orderOut(nil)
        let finished = self
        onClosed?(finished)
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    // MARK: - Busy-state title (justty port)

    /// Target/selector keeps the tick on the main run loop and matches the
    /// AppDelegate's observer style; the timer retains self until close()
    /// invalidates it, which every teardown path (window close button,
    /// Cmd+W, shell exit, app quit) reaches through close().
    private func startTitlePolling() {
        let timer = Timer(
            timeInterval: BusyTitle.pollInterval,
            target: self,
            selector: #selector(titlePollTick),
            userInfo: nil,
            repeats: true
        )
        // Common mode keeps ticking while menus are tracked or a window
        // drag runs, where the default mode would pause the poll.
        RunLoop.main.add(timer, forMode: .common)
        titlePollTimer = timer
        titlePollTick()
    }

    private func stopTitlePolling() {
        titlePollTimer?.invalidate()
        titlePollTimer = nil
    }

    @objc private func titlePollTick() {
        guard !closed else {
            stopTitlePolling()
            return
        }
        refreshTitleFromForeground()
    }

    private func refreshTitleFromForeground() {
        let foreground = surface.terminalView.foregroundPid
        let name = foreground.flatMap(BusyTitle.processName(for:))
        let result = BusyTitle.hasRunningCommand(
            foregroundPid: foreground,
            foregroundName: name,
            shellName: shellName,
            shellPid: shellPid
        )
        shellPid = result.lockedShellPid
        let title = BusyTitle.displayTitle(isBusy: result.isBusy, foregroundName: name)
        if window.title != title {
            window.title = title
        }
    }
}
