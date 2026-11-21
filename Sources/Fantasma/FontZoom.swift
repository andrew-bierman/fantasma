import GhosttyTerminal

/// Per-surface font zoom (⌘= / ⌘+ / ⌘− / ⌘0): tracks the signed step away
/// from the config default and applies it through Ghostty binding actions
/// on the live surface. Writing `TerminalSurfaceOptions.fontSize` instead
/// would rebuild the surface and kill the shell — the coordinator rebuilds
/// whenever options stop being equivalent and fontSize takes part in that
/// comparison — so zoom rides the same action path as the library's own
/// pinch zoom. Bounds mirror its clamp (4…64).
@MainActor
final class FontZoom {
    enum Direction {
        case increase
        case decrease
        case reset

        /// Key character → direction. `charactersIgnoringModifiers` keeps
        /// Shift, so ⌘+ arrives as "+" and ⌘= as "="; the keypad
        /// plus/minus/zero keys produce the same characters.
        init?(matching key: String?) {
            switch key {
            case "=", "+": self = .increase
            case "-": self = .decrease
            case "0": self = .reset
            default: return nil
            }
        }
    }

    private static let minFontSize = 4
    private static let maxFontSize = 64

    /// Signed points away from the config default; 0 is the default.
    private(set) var step = 0

    private let defaultFontSize: Int

    init(defaultFontSize: Int) {
        self.defaultFontSize = defaultFontSize
    }

    /// Applies one zoom direction to the surface's terminal view. The
    /// tracked step moves only when the binding actually dispatched (no
    /// surface up yet reports false), so it never drifts from what the
    /// renderer shows.
    func apply(_ direction: Direction, on view: TerminalView) {
        switch direction {
        case .increase:
            guard zoomedFontSize < FontZoom.maxFontSize else { return }
            if view.performBindingAction("increase_font_size:1") {
                step += 1
            }
        case .decrease:
            guard zoomedFontSize > FontZoom.minFontSize else { return }
            if view.performBindingAction("decrease_font_size:1") {
                step -= 1
            }
        case .reset:
            if view.performBindingAction("reset_font_size") {
                step = 0
            }
        }
    }

    private var zoomedFontSize: Int {
        defaultFontSize + step
    }
}
