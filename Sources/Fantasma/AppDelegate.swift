import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var surface: TerminalSurface?
    private var gate = SummonGate()
    private var activationRetry: DispatchWorkItem?
    private var armHold: DispatchWorkItem?
    private var keyMonitor: Any?
    private var reopenTimestamp: Date?
    private var isQuitting = false
    private var normalWindows: [NormalWindowController] = []
    private let pinned = CommandLine.arguments.contains("--pin")
    private var config = FantasmaConfigLoader.load()
    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?

    private let cornerRadius: CGFloat = 14

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory first: flipping the policy while active resigns active
        // immediately (KTD3).
        NSApp.setActivationPolicy(.accessory)

        let frame = OverlayGeometry.frame(
            for: NSScreen.main?.visibleFrame ?? .zero,
            config: config
        )
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
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
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
                // Zoom keys first (⌘=/⌘+/⌘−/⌘0); they never collide with
                // the window commands below.
                if let direction = FontZoom.Direction(matching: event.charactersIgnoringModifiers) {
                    self?.surface?.applyFontZoom(direction)
                    return nil
                }
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
            if let normal = self?.normalWindows.first(where: { $0.window === event.window }) {
                if let direction = FontZoom.Direction(matching: event.charactersIgnoringModifiers) {
                    normal.applyFontZoom(direction)
                    return nil
                }
                switch event.charactersIgnoringModifiers {
                case "w":
                    normal.close()
                    return nil
                case ",":
                    self?.openSettings(nil)
                    return nil
                default:
                    return event
                }
            } else if event.window === self?.window, event.charactersIgnoringModifiers == "," {
                self?.openSettings(nil)
                return nil
            }
            return event
        }

        // suspensionBehavior .deliverImmediately: macOS naps hidden
        // accessory apps, and the default (.coalesce) drops distributed
        // posts to them — the CLI would summon nothing.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(newWindowRequested(_:)),
            name: .fantasmaNewWindow,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggleFloatRequested(_:)),
            name: .fantasmaToggleFloat,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reloadConfigRequested(_:)),
            name: .fantasmaReloadConfig,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        // System light/dark switch: retint theme pairs live, no restart
        // (deliverImmediately — napping accessory apps drop coalesced posts).
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged(_:)),
            name: .appleInterfaceThemeChanged,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        self.window = window
        show()
        installMainMenu()
        registerGlobalHotkey()
    }

    /// The menu bar only exists while Fantasma runs with the regular
    /// activation policy (a normal window is focused); the float returns to
    /// accessory, which hides it again.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "About Fantasma",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit Fantasma",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(
            title: "New Tiled Window",
            action: #selector(newWindowRequested(_:)),
            keyEquivalent: "n"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings(_ sender: Any?) {
        let path = FantasmaConfigLoader.ensureDefaultFile()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotkey()
        NSEvent.removeMonitor(keyMonitor as Any)
        keyMonitor = nil
        surface?.teardown()
        surface = nil
        // Snapshot + clear before closing: close() mutates normalWindows
        // through onClosed, and mutating during enumeration traps.
        let closing = normalWindows
        normalWindows.removeAll()
        for controller in closing {
            controller.window.delegate = nil
            controller.close()
        }
    }

    @objc private func windowDidResize(_ notification: Notification) {
        surface?.fitToSize()
    }

    @objc private func focusLost(_ notification: Notification) {
        guard !pinned else { return }
        switch gate.focusLost() {
        case .hide:
            fantasmaLog("focus lost → hide")
            hide()
        case .reattempt:
            // Never resurrect a hidden window; only fight back while visible.
            guard let window, window.isVisible, activationRetry == nil, armHold == nil else { return }
            fantasmaLog("focus lost during summon → re-activate")
            activateAttempt()
        case .ignore:
            break
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Cmd-Tab back to a hidden Fantasma must re-summon the float —
        // activation alone leaves the app active with no visible window
        // and dead input. Ignore activation during our own hide path.
        guard !pinned, !isQuitting, let window else { return }
        if !window.isVisible {
            show()
        } else if !gate.armed, activationRetry == nil, armHold == nil {
            // Fresh launch: LaunchServices activation arrived after show()'s
            // handshake ran; complete it now.
            activateAttempt()
        }
    }

    @objc private func newWindowRequested(_ notification: Notification) {
        openNormalWindow()
    }

    @objc private func toggleFloatRequested(_ notification: Notification) {
        toggle()
    }

    /// System appearance flipped: apply the pair's matching side to every
    /// live surface in place (shells keep running). The controller no-ops
    /// on repeated identical themes, so duplicate posts are harmless.
    @objc private func systemAppearanceChanged(_ notification: Notification) {
        let name = TerminalSurface.effectiveThemeName(for: config)
        surface?.applyTheme(named: name)
        for controller in normalWindows {
            controller.applyTheme(named: name)
        }
    }

    @objc private func reloadConfigRequested(_ notification: Notification) {
        let previous = config
        config = FantasmaConfigLoader.load()
        guard config != previous else { return }
        // Hard rule: live shells survive a reload. New windows already read
        // `config` at creation, so every future surface picks up the new
        // values with no further work. The one safe in-place refresh is the
        // float's surface under clear_on_open — that shell dies on the next
        // hide anyway, so rebuilding it now honors theme/font/padding
        // immediately; with clear_on_open off the float keeps its surface
        // until relaunch.
        guard config.clearOnOpen, let window else { return }
        let surfaceChanged = config.theme != previous.theme
            || config.themeLight != previous.themeLight
            || config.themeDark != previous.themeDark
            || config.fontSize != previous.fontSize
            || config.padding != previous.padding
            || config.fontFamily != previous.fontFamily
            || config.copyOnSelect != previous.copyOnSelect
        guard surfaceChanged, let surface else { return }
        surface.teardown()
        self.surface = nil
        attachSurface(to: window, frame: NSRect(origin: .zero, size: window.frame.size))
        // Re-anchor input only when the float already owns it; never steal
        // focus from another app because a config file changed.
        if window.isKeyWindow {
            focusContent()
        }
    }

    private func openNormalWindow() {        let controller = NormalWindowController(config: config)
        controller.onClosed = { [weak self] finished in
            self?.normalWindows.removeAll { $0 === finished }
            // Last normal window closed: drop the menu bar by returning to
            // accessory (the float re-upgrades to accessory on its own show).
            if self?.normalWindows.isEmpty == true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        normalWindows.append(controller)
        controller.show()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        // Menu bar presence follows the focused window: a normal window
        // upgrades to .regular (menu bar appears); the overlay never
        // downgrades while active — losing the menu bar mid-activation
        // would resign and self-hide.
        guard let focused = notification.object as? NSWindow else { return }
        if normalWindows.contains(where: { $0.window === focused }) {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func quitFromShellExit() {
        guard !isQuitting else { return }
        isQuitting = true
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Our own LS activation request (see activateAttempt) lands here
        // while the summon handshake is running: do not treat it as a
        // toggle — it would hide the float we are trying to summon.
        if let window, window.isVisible, !gate.armed {
            return false
        }
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
        gate.showRequested()
        cancelSummonTimers()
        if surface == nil {
            attachSurface(
                to: window,
                frame: NSRect(origin: .zero, size: window.frame.size)
            )
        }
        window.makeKeyAndOrderFront(nil)
        focusContent()
        fantasmaLog("show")
        activateAttempt()
    }

    /// Fight for focus until it actually sticks, instead of assuming a fixed
    /// latch is long enough: launch activation and WM focus bounce can both
    /// arrive later than any constant we pick.
    private func activateAttempt() {
        guard let window, !gate.dismissed else { return }
        NSApp.activate(ignoringOtherApps: true)
        switch gate.activationCheck(isActive: NSApp.isActive, isKey: window.isKeyWindow) {
        case .focused:
            fantasmaLog("activation focused — arm hold starts")
            scheduleArmHold()
        case .retry:
            fantasmaLog("activation retry in 0.25s (\(gate.attemptsLeft) left)")
            // NSApp.activate is refused outright on modern macOS unless the
            // system deems us activation-eligible; LaunchServices-mediated
            // activation (reopen on our own bundle) carries real system
            // rights and is the path that reliably works. Fire it after the
            // first two plain attempts have failed.
            if gate.attemptsLeft <= 4 {
                let bundlePath = Bundle.main.bundlePath
                if !bundlePath.isEmpty {
                    fantasmaLog("requesting LS reopen activation")
                    NSWorkspace.shared.open(URL(fileURLWithPath: bundlePath))
                }
            }
            let work = DispatchWorkItem { [weak self] in self?.activateAttempt() }
            activationRetry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        case .gaveUp:
            fantasmaLog("activation gave up: active=\(NSApp.isActive) key=\(window.isKeyWindow)")
        }
    }

    private func scheduleArmHold() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            if self.gate.holdElapsed(isActive: NSApp.isActive, isKey: window.isKeyWindow) {
                fantasmaLog("armed")
            } else {
                fantasmaLog("focus lost mid-hold — re-attempting")
                self.activateAttempt()
            }
        }
        armHold = work
        // 1.0 s: sampled WM focus bounce (yabai restoring the terminal)
        // lands ~0.2–0.3 s AFTER a successful arm on this setup — a 0.5 s
        // hold arms right before the bounce and the float flashes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func cancelSummonTimers() {
        activationRetry?.cancel()
        activationRetry = nil
        armHold?.cancel()
        armHold = nil
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
        // Dismiss the gate first: orderOut fires didResignKey, and an
        // armed gate would route that into a re-summon fight.
        cancelSummonTimers()
        gate.hid()
        guard let window, window.isVisible else { return }
        fantasmaLog("hide")
        window.orderOut(nil)
        // clear_on_open (R17): the shell dies here by design; the surface's
        // expected-teardown state keeps this off the quit path (KTD14).
        if config.clearOnOpen {
            surface?.teardown()
            surface = nil
            // Release the dead Metal view tree instead of retaining it as
            // invisible contentView content between summons.
            window.contentView = nil
        }
    }

    // MARK: - Global hotkey

    /// Carbon RegisterEventHotKey rather than an NSEvent global monitor:
    /// an accessory app with no key windows still receives Carbon hotkey
    /// events, and the keystroke is consumed. Empty config leaves the
    /// feature off; invalid input warns and stays off. Fires the same
    /// toggle path as the distributed toggle-float handler.
    private func registerGlobalHotkey() {
        switch HotkeyParser.parse(config.hotkey) {
        case .disabled:
            return
        case .invalid(let raw):
            fantasmaLog("hotkey config \"\(raw)\" is invalid — disabled (expected e.g. cmd+grave)")
            return
        case .hotkey(let binding):
            var eventTypes = [EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )]
            // The C callback cannot capture; the AppDelegate lives for the
            // whole process (main() retains it), so an unretained pointer
            // is safe. Carbon dispatches hotkey events on the main thread.
            let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    MainActor.assumeIsolated {
                        delegate.hotkeyFired()
                    }
                    return noErr
                },
                eventTypes.count,
                &eventTypes,
                userData,
                &hotkeyHandler
            )
            guard installStatus == noErr else {
                fantasmaLog("hotkey handler install failed: \(installStatus)")
                return
            }
            var ref: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                EventHotKeyID(signature: OSType(0x4648_4B59), id: 1), // 'FHKY'
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard registerStatus == noErr else {
                fantasmaLog("hotkey register failed: \(registerStatus)")
                return
            }
            hotkeyRef = ref
            fantasmaLog("hotkey registered")
        }
    }

    private func unregisterGlobalHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = hotkeyHandler {
            RemoveEventHandler(handler)
            hotkeyHandler = nil
        }
    }

    private func hotkeyFired() {
        toggle()
    }
}
