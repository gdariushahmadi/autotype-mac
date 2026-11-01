import Foundation
import Carbon
import SwiftUI

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

    /// The sentence under the title: what to do about it.
    var subtitle: String {
        switch self {
        case .notInstalled:
            return "AutoType has not been added to your input sources yet."
        case .installed:
            return "Open Keyboard Settings → Text Input → Edit, add AutoType, and switch to it with Control + Space."
        case .enabled:
            return "AutoType is switched on. Keep typing on the English layout — Persian words are converted as you finish them."
        case .unknown:
            return "Asking macOS whether AutoType is installed…"
        }
    }

    /// The symbol that carries the state.
    var symbol: String {
        switch self {
        case .enabled: return "checkmark.circle.fill"
        case .installed, .notInstalled: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// The colour of the symbol.
    var tint: Color {
        switch self {
        case .enabled: return .green
        case .installed, .notInstalled: return .orange
        case .unknown: return .secondary
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
