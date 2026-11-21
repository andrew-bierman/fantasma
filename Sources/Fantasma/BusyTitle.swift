import Darwin
import Foundation

/// Busy-state window titles for normal windows, ported from justty's
/// TerminalSession (github.com/0x96f/justty): the pty's foreground process
/// group pid (tcgetpgrp) is polled against the login shell's pid — while a
/// foreground command runs the title shows its basename, when idle it is
/// the plain app name. The pure policy lives here so tests can drive it
/// without a live pty; only NormalWindowController ever calls it. The
/// overlay float's title ("fantasma-float") is yabai-matched and must
/// never change.
enum BusyTitle {
    /// Justty's cadence: fast enough to feel immediate, slow enough to
    /// stay off the hot path.
    static let pollInterval: TimeInterval = 0.5

    /// Idle title; a busy window shows "fantasma — <command basename>".
    static let idleTitle = "fantasma"

    /// Pure busy policy: is a foreground command running (as opposed to
    /// the login shell), and the shell pid this sample locks. Once
    /// identified, process identity wins over names — a child shell can
    /// share the login shell's basename — so a locked shellPid is cleared
    /// exactly when the foreground stops being it, and re-locked by
    /// basename only while unidentified. Before the shell pid is observed,
    /// the `/bin/sh -c 'exec <shell> -l'` wrapper Fantasma launches
    /// through is ignored rather than shown as a running command.
    static func hasRunningCommand(
        foregroundPid: pid_t?,
        foregroundName: String?,
        shellName: String,
        shellPid: pid_t?
    ) -> (isBusy: Bool, lockedShellPid: pid_t?) {
        guard let foregroundPid else {
            return (false, nil)
        }
        if let shellPid {
            let isShell = foregroundPid == shellPid
            return (!isShell, isShell ? shellPid : nil)
        }
        if foregroundName == shellName {
            return (false, foregroundPid)
        }
        let isBusy = foregroundName != nil && foregroundName != "sh"
        return (isBusy, nil)
    }

    /// Window title for one sample: "fantasma — vim" while a command
    /// runs, "fantasma" at the shell prompt (and when the foreground's
    /// name is unreadable).
    static func displayTitle(isBusy: Bool, foregroundName: String?) -> String {
        guard isBusy, let foregroundName, !foregroundName.isEmpty else {
            return idleTitle
        }
        return "\(idleTitle) — \(foregroundName)"
    }

    /// Basename of a pid's executable: proc_pidpath first (full path, so
    /// names past the 15-char process-name clamp survive), proc_name as
    /// fallback.
    static func processName(for pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE (libproc.h): the #define is not
        // imported into Swift, so spell out its documented value.
        let pidPathBufferSize = 4_096
        var path = [CChar](repeating: 0, count: pidPathBufferSize)
        if proc_pidpath(pid, &path, UInt32(pidPathBufferSize)) > 0 {
            let basename = (string(from: path) as NSString).lastPathComponent
            if !basename.isEmpty {
                return basename
            }
        }
        var name = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        guard proc_name(pid, &name, UInt32(MAXCOMLEN)) > 0 else { return nil }
        return string(from: name)
    }

    /// Null-terminated CChar buffer → String, without the deprecated
    /// array-targeted String(cString:) initializer.
    private static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
