import Foundation

/// One-line-per-transition log for diagnosing summon/focus timing issues.
/// ~/Library/Logs/fantasma.log, truncated at 1 MB so it stays bounded.
@MainActor
func fantasmaLog(_ message: String) {
    let path = NSHomeDirectory() + "/Library/Logs/fantasma.log"
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let line = "[\(formatter.string(from: Date()))] \(message)\n"
    guard let handle = FileHandle(forWritingAtPath: path) else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        return
    }
    defer { try? handle.close() }
    if (try? handle.seekToEnd()) ?? 0 > 1_000_000 {
        try? handle.truncate(atOffset: 0)
    }
    try? handle.seekToEnd()
    try? handle.write(line.data(using: .utf8)!)
}
