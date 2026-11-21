import Foundation

/// Tracks the working directory each live terminal surface last reported
/// (OSC 7, delivered by libghostty's `TerminalSurfacePwdDelegate`) and
/// which surface was most recently active, so a newly spawned shell — the
/// float on its next summon and every new normal window — starts where the
/// user last was instead of always at home.
///
/// Pure value type: the app layer owns one instance and feeds it from the
/// surface's working-directory callback and key-window changes. Surfaces
/// are identified by `ObjectIdentifier`, which stays stable for the life
/// of the surface and never collides across windows.
struct LastWorkingDirectory {
    /// Spawned shells land here when nothing better is known; matches the
    /// pre-feature behaviour of always spawning at `NSHomeDirectory()`.
    let fallback: String

    private var directories: [ObjectIdentifier: String] = [:]
    private var active: ObjectIdentifier?

    init(fallback: String = NSHomeDirectory()) {
        self.fallback = fallback
    }

    /// A surface emitted OSC 7. Only real filesystem paths are kept: the
    /// shell integration reports a decoded path, but anything else (a raw
    /// file:// URL, an empty string) is unusable for spawning and would
    /// poison every later summon, so it is dropped here.
    mutating func record(_ surface: ObjectIdentifier, directory: String) {
        guard directory.hasPrefix("/"), directory.count > 1 else { return }
        directories[surface] = directory
    }

    /// Marks a surface active (its window became key, or the float was
    /// summoned); its last reported directory is what new shells inherit.
    mutating func activate(_ surface: ObjectIdentifier) {
        active = surface
    }

    /// Forgets a dead surface so its identifier and path are not retained
    /// for the rest of the process.
    mutating func remove(_ surface: ObjectIdentifier) {
        directories[surface] = nil
        if active == surface {
            active = nil
        }
    }

    /// The directory of the most recently active surface, if it reported
    /// one. Tests and app code both read through `spawnDirectory`.
    var current: String? {
        active.flatMap { directories[$0] }
    }

    /// Where the next shell should spawn: the active surface's directory
    /// when it still exists on disk (a shell can report a path that was
    /// deleted since, and spawning into a missing directory would fail the
    /// surface), else the fallback.
    func spawnDirectory(fileManager: FileManager = .default) -> String {
        if let path = current {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return path
            }
        }
        return fallback
    }
}
