import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var surface: TerminalSurface?
    private var ignoresFocusLoss = false
    private var keyMonitor: Any?
    private var reopenTimestamp: Date?
    private var isQuitting = false
    /// Debug: `--pin` disables auto-hide so scripted probes can inspect the
    /// window without fighting focus loss. Not used by normal operation.
    private let pinned = CommandLine.arguments.contains("--pin")

    private let cornerRadius: CGFloat = 14

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory first: flipping the policy while active resigns active
        // immediately (KTD3).
        NSApp.setActivationPolicy(.accessory)

        let frame = OverlayGeometry.frame(for: NSScreen.main?.visibleFrame ?? .zero)
        let window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = OverlayGeometry.minimumSize

        let contentFrame = NSRect(origin: .zero, size: frame.size)
        let surface = TerminalSurface(frame: contentFrame)
        surface.onShellExit = { [weak self] in
            self?.quitFromShellExit()
        }
        surface.terminalView.wantsLayer = true
        surface.terminalView.layer?.cornerRadius = cornerRadius
        surface.terminalView.layer?.masksToBounds = true
        window.contentView = surface.terminalView

        // Borderless windows get no standard edge-resize affordance from
        // .resizable alone; the controller view supplies it (KTD11).
        let edges = EdgeResizeControllerView(frame: contentFrame)
        edges.translatesAutoresizingMaskIntoConstraints = false
        surface.terminalView.addSubview(edges)
        NSLayoutConstraint.activate([
            edges.topAnchor.constraint(equalTo: surface.terminalView.topAnchor),
            edges.bottomAnchor.constraint(equalTo: surface.terminalView.bottomAnchor),
            edges.leadingAnchor.constraint(equalTo: surface.terminalView.leadingAnchor),
            edges.trailingAnchor.constraint(equalTo: surface.terminalView.trailingAnchor),
        ])

        // Keep the grid fitted to the window as it resizes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // Cmd+W hides, Cmd+Q quits; a borderless window has no menu bar to
        // carry key equivalents (KTD6).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === self?.window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function) == .command
            else { return event }
            switch event.charactersIgnoringModifiers {
            case "w":
                self?.hide()
                return nil
            case "q":
                NSApp.terminate(nil)
                return nil
            default:
                return event
            }
        }

        self.window = window
        self.surface = surface
        show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Tear the surface down explicitly so the PTY does not linger.
        surface?.terminalView.controller = nil
        surface = nil
    }

    @objc private func windowDidResize(_ notification: Notification) {
        surface?.fitToSize()
    }

    private func quitFromShellExit() {
        guard !isQuitting else { return }
        isQuitting = true
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launcher double-fire debounce (~200 ms) so one hotkey tap cannot
        // toggle twice (KTD4).
        if let last = reopenTimestamp, Date().timeIntervalSince(last) < 0.2 {
            return false
        }
        reopenTimestamp = Date()
        toggle()
        return false
    }

    // MARK: - Show / hide / toggle

    private func toggle() {
        guard let window else { return }
        if window.isVisible {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        guard let window else { return }
        ignoresFocusLoss = true
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusContent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.ignoresFocusLoss = false
        }
    }

    private func focusContent() {
        // The Ghostty surface becomes first responder via its own focus
        // path; the binding lands only after the view mounts, so retry
        // with a hard cap instead of spinning (KTD4).
        guard let window, let surface else { return }
        surface.focus()
        guard window.firstResponder === window else { return }
        var attempts = 0
        func retry() {
            guard attempts < 10 else { return }
            attempts += 1
            surface.focus()
            if window.firstResponder === window {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { retry() }
            }
        }
        retry()
    }

    private func hide() {
        window?.orderOut(nil)
    }

    // MARK: - Focus loss

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard !pinned, !ignoresFocusLoss else { return }
        hide()
    }

    @objc private func appDidResignActive(_ notification: Notification) {
        guard !pinned, !ignoresFocusLoss else { return }
        hide()
    }
}
