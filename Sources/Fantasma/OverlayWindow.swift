import AppKit

/// Borderless windows refuse key status by default, which would silently
/// drop every keystroke; an overlay terminal must be able to become key
/// and main (KTD2).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
