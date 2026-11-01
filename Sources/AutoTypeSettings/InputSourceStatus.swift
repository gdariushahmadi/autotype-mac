import Foundation
import Carbon

/// Whether the AutoType input method is installed and switched on.
enum InputSourceStatus {

    /// The input method is not installed in `~/Library/Input Methods`.
    case notInstalled
    /// It is installed but not added to the active input sources.
    case installed
    /// It is installed and enabled.
    case enabled
    /// The status could not be determined.
    case unknown

    var title: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed — add it to your input sources"
        case .enabled: return "Active"
        case .unknown: return "Checking…"
        }
    }

    var isUsable: Bool {
        if case .enabled = self { return true }
        return false
    }

    /// Asks the text input system about AutoType.
    static func current() -> InputSourceStatus {
        let installed = containsAutoType(includeAllInstalled: true)
        guard installed else { return .notInstalled }
        return containsAutoType(includeAllInstalled: false) ? .enabled : .installed
    }

    private static func containsAutoType(includeAllInstalled: Bool) -> Bool {
        guard let unmanaged = TISCreateInputSourceList(nil, includeAllInstalled) else { return false }
        let list = unmanaged.takeRetainedValue()
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
            guard let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let identifier = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
            if identifier.localizedCaseInsensitiveContains("autotype") { return true }
        }
        return false
    }
}
