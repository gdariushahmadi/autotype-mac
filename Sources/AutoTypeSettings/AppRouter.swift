import AppKit

/// Lets the parts of the app that are not SwiftUI views reach the settings
/// window.
///
/// The window is opened by the menu bar label, which is the first thing the
/// app builds and therefore the only place that knows how to open it.
final class AppRouter {

    static let shared = AppRouter()

    static let settingsWindowID = "autotype-settings"

    /// Set as soon as the app is running.
    var openSettings: (() -> Void)?

    /// The part of the window to open on, when something asks for one.
    var pendingSection: SettingsSection?
}
