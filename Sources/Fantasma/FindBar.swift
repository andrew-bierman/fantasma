import AppKit
import GhosttyTerminal

/// Per-surface scrollback find bar (⌘F): a small chrome-less field pinned
/// inside the host window's content, driving the engine's search thread
/// through Ghostty binding actions — the same protocol ghostty's own GTK
/// search overlay uses (`search:<needle>`, `navigate_search:*`,
/// `end_search`). The engine matches the screen plus the full scrollback
/// case-insensitively, highlights every viewport match, highlights the
/// selected match stronger, and scrolls the viewport to it when it is
/// off-screen.
///
/// Match counts (`GHOSTTY_ACTION_SEARCH_TOTAL/SEARCH_SELECTED`) exist in
/// the engine but libghostty-spm's callback bridge drops them in its
/// default action branch, so the bar has no "k of n" label; nothing here
/// pretends otherwise.
@MainActor
final class FindBarController: NSObject {
    /// Navigation direction for `navigate_search`.
    enum Direction: String {
        case next
        case previous
    }

    /// Engine binding-action strings. The engine splits an action at the
    /// first colon only, so a needle reaches it verbatim — spaces and
    /// further colons included. An empty needle stops the search thread.
    enum Action {
        static let endSearch = "end_search"

        static func search(needle: String) -> String {
            "search:" + needle
        }

        static func navigate(_ direction: Direction) -> String {
            "navigate_search:" + direction.rawValue
        }
    }

    private static let panelWidth: CGFloat = 220
    private static let panelHeight: CGFloat = 28
    private static let panelInset: CGFloat = 12

    let panel: NSVisualEffectView
    private let field = NSTextField(string: "")
    /// Weak because the float rebuilds surface + bar together on teardown
    /// (clear_on_open) while a stale bar can briefly outlive its surface.
    private weak var surface: TerminalSurface?
    private(set) var isShown = false

    init(surface: TerminalSurface) {
        self.surface = surface

        let panel = NSVisualEffectView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: FindBarController.panelWidth,
                height: FindBarController.panelHeight
            )
        )
        panel.material = .hudWindow
        panel.blendingMode = .behindWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 8
        panel.layer?.masksToBounds = true

        field.placeholderString = "Find"
        field.focusRingType = .none
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = .white
        field.lineBreakMode = .byTruncatingHead
        field.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(
                equalTo: panel.leadingAnchor, constant: 10
            ),
            field.trailingAnchor.constraint(
                equalTo: panel.trailingAnchor, constant: -10
            ),
            field.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
        ])

        self.panel = panel
        super.init()
        field.delegate = self
    }

    /// Pins the bar into a host's content view, hidden until first open.
    /// The float passes its rounded content container; a normal window
    /// passes its terminal view (the EdgeResizeControllerView precedent
    /// for hosting subviews on the engine's view).
    func attach(to host: NSView) {
        panel.isHidden = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(
                equalTo: host.topAnchor, constant: FindBarController.panelInset
            ),
            panel.trailingAnchor.constraint(
                equalTo: host.trailingAnchor, constant: -FindBarController.panelInset
            ),
            panel.widthAnchor.constraint(equalToConstant: FindBarController.panelWidth),
            panel.heightAnchor.constraint(equalToConstant: FindBarController.panelHeight),
        ])
    }

    /// ⌘F semantics: open when closed, close when the field is focused,
    /// and just refocus the field when a click moved focus to the shell.
    func toggle() {
        if isShown, fieldIsFocused {
            close()
        } else if isShown {
            field.window?.makeFirstResponder(field)
        } else {
            open()
        }
    }

    func open() {
        guard !isShown else { return }
        isShown = true
        panel.isHidden = false
        fantasmaLog("find open")
        field.window?.makeFirstResponder(field)
    }

    /// Closes the bar and stops the engine search. The needle is cleared
    /// so the next ⌘F starts fresh; the terminal refocuses so typing
    /// lands in the shell again.
    func close() {
        guard isShown else { return }
        isShown = false
        panel.isHidden = true
        fantasmaLog("find close")
        _ = surface?.terminalView.performBindingAction(Action.endSearch)
        field.stringValue = ""
        // Refocusing the terminal also ends the field editor's edit session.
        surface?.focus()
    }

    private var fieldIsFocused: Bool {
        field.currentEditor() != nil
    }
}

extension FindBarController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        // Live needle updates: the engine restarts the search when the
        // needle changed and keeps its results when it did not. An empty
        // needle stops the search thread.
        let needle = field.stringValue
        _ = surface?.terminalView.performBindingAction(Action.search(needle: needle))
    }

    func control(
        _ control: NSControl,
        textView fieldEditor: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSTextView.insertNewline(_:)):
            // Enter → next match, Shift+Enter → previous. The current
            // event is the keyDown that produced the newline command.
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            _ = surface?.terminalView.performBindingAction(
                Action.navigate(shift ? .previous : .next)
            )
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}
