import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var surface: TerminalSurface?
    private var ignoresFocusLoss = false
    private var keyMonitor: Any?
    private var reopenTimestamp: Date?
    private var isQuitting = false
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

        // The terminal view renders into its own Metal layer, which does not
        // inherit corner clipping; a plain container owns the rounded mask.
        let container = NSView(frame: contentFrame)
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]
        surface.terminalView.frame = contentFrame
        surface.terminalView.autoresizingMask = [.width, .height]
        container.addSubview(surface.terminalView)
        window.contentView = container

        let edgeResizer = EdgeResizeControllerView(frame: contentFrame)
        edgeResizer.translatesAutoresizingMaskIntoConstraints = false
        surface.terminalView.addSubview(edgeResizer)
        NSLayoutConstraint.activate([
            edgeResizer.topAnchor.constraint(equalTo: surface.terminalView.topAnchor),
            edgeResizer.bottomAnchor.constraint(equalTo: surface.terminalView.bottomAnchor),
            edgeResizer.leadingAnchor.constraint(equalTo: surface.terminalView.leadingAnchor),
            edgeResizer.trailingAnchor.constraint(equalTo: surface.terminalView.trailingAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusLost(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusLost(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // A borderless window has no menu bar to carry key equivalents (KTD6).
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
        NSEvent.removeMonitor(keyMonitor as Any)
        keyMonitor = nil
        surface?.teardown()
        surface = nil
    }

    @objc private func windowDidResize(_ notification: Notification) {
        surface?.fitToSize()
    }

    @objc private func focusLost(_ notification: Notification) {
        guard !pinned, !ignoresFocusLoss else { return }
        hide()
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusContent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.ignoresFocusLoss = false
        }
    }

    private func focusContent() {
        // The Ghostty surface becomes first responder via its own focus
        // path; the binding lands only after the view mounts (KTD4).
        guard let window, let surface else { return }
        var attempts = 0
        func attempt() {
            surface.focus()
            guard window.firstResponder === window, window.isVisible, attempts < 10 else { return }
            attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt() }
        }
        attempt()
    }

    private func hide() {
        window?.orderOut(nil)
    }
}
