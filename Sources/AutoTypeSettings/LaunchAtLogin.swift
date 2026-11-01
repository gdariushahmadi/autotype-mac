import Foundation
import ServiceManagement

/// Whether the settings app should start when the user logs in.
///
/// The input method itself is started by macOS whenever a text field needs
/// it, so it never needs a login item; only the settings app does.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("AutoType: could not change the login item: \(error.localizedDescription)")
            return false
        }
    }
}
