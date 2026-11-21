import Foundation

/// Shared across the shim (main.swift) and the resident app
/// (AppDelegate): the windowed-mode trigger broadcast (KTD16).
extension Notification.Name {
    static let fantasmaNewWindow = Notification.Name("com.andrewbierman.fantasma.new-window")
    static let fantasmaToggleFloat = Notification.Name("com.andrewbierman.fantasma.toggle-float")
}
