import AppKit
import AutoTypeCore

/// The few things the settings app asks macOS to do.
///
/// They are kept in one place so that every button in the window reaches the
/// system the same way, and so the URLs that open the right preference pane
/// exist only once.
enum SystemActions {

    // MARK: - The settings window

    /// Brings the settings window to the front.
    static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        AppRouter.shared.openSettings?()
    }

    // MARK: - System Settings

    /// Opens the pane where the input methods are added.
    static func openKeyboardSettings() {
        openSystemPane([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?TextInput",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ])
    }

    /// Opens the pane where the macOS Services are turned on.
    static func openServicesSettings() {
        openSystemPane([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Services",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ])
    }

    private static func openSystemPane(_ candidates: [String]) {
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - AutoType

    /// Restarts the input method, so a change that only the input method reads
    /// is picked up without logging out.
    static func restartInputMethod() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["AutoTypeIME"]
        try? task.run()
    }

    /// Shows the folder that holds the settings and the dictionary.
    static func revealSettingsFolder() {
        let folder = SettingsStore.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Quits the settings app.
    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}
