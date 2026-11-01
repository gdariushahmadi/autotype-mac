import AppKit
import InputMethodKit
import AutoTypeCore

/// The name of the mach connection the input method talks to the system
/// over.
///
/// It has to be the same string as `InputMethodConnectionName` in the
/// bundle's Info.plist, or the system never finds the input method.
let inputMethodConnectionName = "digital_autotype_imk_connection"

/// The principal class of the input method bundle.
///
/// macOS instantiates this class when it loads the input method. It is the
/// object the system talks to, and it owns the `IMKServer` that connects the
/// input method to the running applications.
@objc(AutoTypeInputMethod)
final class InputMethod: NSObject {

    /// The running server, shared with the menu code.
    static private(set) var shared: InputMethod?

    /// The connection to the system's text input clients.
    private(set) var server: IMKServer?

    override init() {
        super.init()
        InputMethod.shared = self
        if server == nil {
            // The app hosts its own connection to the system's text input
            // clients. The controller and delegate class names are read from
            // the bundle's Info.plist (`IMKControllerClass` and
            // `IMKDelegateClass`).
            server = IMKServer(
                name: inputMethodConnectionName,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "digital.autotype.inputmethod.AutoType"
            )
        }
    }

    /// The menu shown when the user opens the input menu in the menu bar.
    func handleMenu(_ sender: Any!) {
        // The menu is built by the active controller; this hook exists so the
        // system has a principal class to talk to.
    }
}
