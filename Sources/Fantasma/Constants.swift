import Foundation

/// Shared across the shim (main.swift) and the resident app
/// (AppDelegate): the windowed-mode trigger broadcast (KTD16).
extension Notification.Name {
    static let fantasmaNewWindow = Notification.Name("com.andrewbierman.fantasma.new-window")
    static let fantasmaToggleFloat = Notification.Name("com.andrewbierman.fantasma.toggle-float")
    static let fantasmaReloadConfig = Notification.Name("com.andrewbierman.fantasma.reload-config")
    /// macOS system-wide appearance switch (system-provided distributed
    /// notification, not ours); Fantasma listens to retint theme pairs live.
    static let appleInterfaceThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
}
