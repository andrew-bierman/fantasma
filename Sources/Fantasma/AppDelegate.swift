import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var ignoresFocusLoss = false
    private var keyMonitor: Any?
    private var reopenTimestamp: Date?
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

        let content = PlaceholderContentView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.masksToBounds = true
        window.contentView = content

        // Borderless windows get no standard edge-resize affordance from
        // .resizable alone; the controller view supplies it (KTD11).
        let edges = EdgeResizeControllerView(frame: content.bounds)
        edges.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(edges)
        NSLayoutConstraint.activate([
            edges.topAnchor.constraint(equalTo: content.topAnchor),
            edges.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edges.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            edges.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

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
        show()
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
        // The focus binding lands only after the content view mounts; retry
        // with a hard cap instead of spinning (KTD4).
        guard let window, let content = window.contentView else { return }
        window.makeFirstResponder(content)
        guard window.firstResponder === window else { return }
        var attempts = 0
        func retry() {
            guard attempts < 10 else { return }
            attempts += 1
            window.makeFirstResponder(content)
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

/// U1 placeholder: an editable text view inside the rounded content view so
/// the keystroke probe can prove the borderless window receives typing.
/// U2 replaces the window content with the terminal surface.
private final class PlaceholderContentView: NSView {
    private let field: NSTextView

    override init(frame frameRect: NSRect) {
        field = NSTextView(frame: frameRect.insetBy(dx: 24, dy: 24))
        super.init(frame: frameRect)
        field.string = "fantasma — U1 window probe"
        field.isEditable = true
        field.backgroundColor = NSColor(red: 0.157, green: 0.161, blue: 0.212, alpha: 1) // #282a36
        field.textColor = .white
        field.autoresizingMask = [.width, .height]
        addSubview(field)
    }

    override var isFlipped: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(field)
        return super.becomeFirstResponder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
