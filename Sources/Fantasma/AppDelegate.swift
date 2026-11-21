import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var surface: TerminalSurface?
    private var ignoresFocusLoss = false
    private var keyMonitor: Any?
    private var reopenTimestamp: Date?
    private var isQuitting = false
    private var normalWindows: [NormalWindowController] = []
    private let pinned = CommandLine.arguments.contains("--pin")
    private let config = FantasmaConfigLoader.load()

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
        // Yabai/AX-visible title for the title-scoped tile exemption (R18,
        // KTD15); invisible in the borderless window itself.
        window.title = "fantasma-float"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = OverlayGeometry.minimumSize

        attachSurface(to: window, frame: NSRect(origin: .zero, size: frame.size))

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

        // A borderless window has no menu bar to carry key equivalents
        // (KTD6); normal windows need the same treatment for Cmd+W.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function) == .command
            else { return event }
            if event.window === self?.window {
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
            if let normal = self?.normalWindows.first(where: { $0.window === event.window }),
               event.charactersIgnoringModifiers == "w" {
                normal.close()
                return nil
            }
            return event
        }

        // Windowed-mode trigger: the binary invoked with --new-window posts
        // this notification and exits (KTD16).
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(newWindowRequested(_:)),
            name: Notification.Name("com.andrewbierman.fantasma.new-window"),
            object: nil
        )

        self.window = window
        show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSEvent.removeMonitor(keyMonitor as Any)
        keyMonitor = nil
        surface?.teardown()
        surface = nil
        for controller in normalWindows {
            controller.window.delegate = nil
            controller.close()
        }
        normalWindows.removeAll()
    }

    @objc private func windowDidResize(_ notification: Notification) {
        surface?.fitToSize()
    }

    @objc private func focusLost(_ notification: Notification) {
        guard !pinned, !ignoresFocusLoss else { return }
        hide()
    }

    @objc private func newWindowRequested(_ notification: Notification) {
        openNormalWindow()
    }

    func openNormalWindow() {
        let controller = NormalWindowController(config: config)
        controller.onClosed = { [weak self] finished in
            self?.normalWindows.removeAll { $0 === finished }
        }
        normalWindows.append(controller)
        controller.show()
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

    // MARK: - Surface lifecycle

    /// Builds a configured surface and installs it as the window's content.
    private func attachSurface(to window: NSWindow, frame: NSRect) {
        let surface = TerminalSurface(frame: frame, config: config)
        surface.onShellExit = { [weak self] in
            self?.quitFromShellExit()
        }

        // The terminal view renders into its own Metal layer, which does not
        // inherit corner clipping; a plain container owns the rounded mask.
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]
        surface.terminalView.frame = frame
        surface.terminalView.autoresizingMask = [.width, .height]
        container.addSubview(surface.terminalView)
        window.contentView = container

        let edgeResizer = EdgeResizeControllerView(frame: frame)
        edgeResizer.translatesAutoresizingMaskIntoConstraints = false
        surface.terminalView.addSubview(edgeResizer)
        NSLayoutConstraint.activate([
            edgeResizer.topAnchor.constraint(equalTo: surface.terminalView.topAnchor),
            edgeResizer.bottomAnchor.constraint(equalTo: surface.terminalView.bottomAnchor),
            edgeResizer.leadingAnchor.constraint(equalTo: surface.terminalView.leadingAnchor),
            edgeResizer.trailingAnchor.constraint(equalTo: surface.terminalView.trailingAnchor),
        ])

        self.surface = surface
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
        // clear_on_open: dismissal tore the shell down, so every summon is a
        // fresh session (R17). Without it the same surface returns (v1).
        if surface == nil {
            attachSurface(
                to: window,
                frame: NSRect(origin: .zero, size: window.frame.size)
            )
        }
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
        guard let window else { return }
        window.orderOut(nil)
        // clear_on_open (R17): the shell dies here by design; the surface's
        // expected-teardown state keeps this off the quit path (KTD14).
        if config.clearOnOpen {
            surface?.teardown()
            surface = nil
        }
    }
}
