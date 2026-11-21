import AppKit
import Foundation

/// The float window's last on-screen frame, persisted between launches in
/// a small TOML-style state file (`key = value` lines, the same shape as
/// fantasma.conf) at
/// `~/Library/Application Support/Fantasma/state.toml`.
///
/// Precedence when placing the float: the user's config
/// (`float_width`/`float_height`/`float_x`/`float_y`) wins over this state,
/// and state wins over the built-in defaults — config is a deliberate
/// instruction, state is just where the user left the window. Coordinates
/// follow the config convention: `x` is points from the visible frame's
/// left edge, `y` points from its top edge, so the frame survives screen
/// and workspace changes better than absolute coordinates. Values derived
/// from state are clamped into the current visible frame; config values
/// pass through untouched (OverlayGeometry governs them today).
///
/// Pure value type: parsing, serialization and clamping are testable
/// without a window; the app layer loads on launch and stores on
/// hide/resize-end/quit.
struct FloatFrameState: Equatable {
    var x: Int?
    var y: Int?
    var width: Int?
    var height: Int?

    static let fileName = "state.toml"

    /// Default location under Application Support; `directory` is created
    /// on store so a fresh install can persist its first frame.
    static func defaultPath(fileManager: FileManager = .default) -> String {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Fantasma", isDirectory: true)
            .appendingPathComponent(fileName)
            .path
    }

    // MARK: - Serialization

    func serialized() -> String {
        var lines = ["# fantasma float frame state (written by the app)"]
        if let x { lines.append("x = \(x)") }
        if let y { lines.append("y = \(y)") }
        if let width { lines.append("width = \(width)") }
        if let height { lines.append("height = \(height)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses the state file's text. Tolerates corruption by design: any
    /// line that is not `key = value` with an integer value is skipped, so
    /// a truncated or hand-mangled file degrades to "no frame known"
    /// instead of failing the launch path.
    static func parse(_ text: String) -> FloatFrameState {
        var state = FloatFrameState()
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard let number = Int(value) else { continue }
            switch key {
            case "x": state.x = number
            case "y": state.y = number
            case "width": state.width = number
            case "height": state.height = number
            default: break
            }
        }
        return state
    }

    /// Reads the state file; nil when absent or unreadable (caller falls
    /// back to config/defaults).
    static func load(path: String) -> FloatFrameState? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return parse(text)
    }

    /// Writes the file atomically, creating the parent directory first
    /// (Application Support/Fantasma does not exist on a fresh install).
    func store(path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        try serialized().write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Conversion

    /// Captures a live window frame using the config coordinate
    /// convention (see the precedence comment); the inverse of placing
    /// that state back through `OverlayGeometry`.
    static func from(frame: NSRect, visibleFrame: NSRect) -> FloatFrameState {
        FloatFrameState(
            x: Int((frame.minX - visibleFrame.minX).rounded()),
            y: Int((visibleFrame.maxY - frame.maxY).rounded()),
            width: Int(frame.width.rounded()),
            height: Int(frame.height.rounded())
        )
    }

    /// State-derived values clamped to what the current visible frame can
    /// host: sizes stay between the float minimum and the full frame, and
    /// the origin keeps the whole window on-screen. Partial state (say,
    /// only a saved width) clamps against the effective values after the
    /// merge, so every field resolves consistently.
    static func merged(into config: FantasmaConfig, state: FloatFrameState?, visibleFrame: NSRect) -> FantasmaConfig {
        var resolved = config
        let minWidth = Int(OverlayGeometry.minimumSize.width)
        let minHeight = Int(OverlayGeometry.minimumSize.height)

        // Config wins over state wins over defaults: nil config fields
        // fill from the state file, and only the state-derived values
        // clamp to what the current visible frame can host.
        resolved.floatWidth = config.floatWidth
            ?? clamp(state?.width, low: minWidth, high: Int(visibleFrame.width))
        resolved.floatHeight = config.floatHeight
            ?? clamp(state?.height, low: minHeight, high: Int(visibleFrame.height))

        let effectiveWidth = resolved.floatWidth ?? Int(OverlayGeometry.defaultSize.width)
        let effectiveHeight = resolved.floatHeight ?? Int(OverlayGeometry.defaultSize.height)
        resolved.floatX = config.floatX
            ?? clamp(state?.x, low: 0, high: Int(visibleFrame.width) - effectiveWidth)
        resolved.floatY = config.floatY
            ?? clamp(state?.y, low: 0, high: Int(visibleFrame.height) - effectiveHeight)
        return resolved
    }

    private static func clamp(_ value: Int?, low: Int, high: Int) -> Int? {
        guard let value else { return nil }
        // A degenerate range (screen smaller than the minimum) floors at
        // `low`; OverlayGeometry then shrinks the size to what fits.
        let upper = max(low, high)
        return min(max(value, low), upper)
    }
}
