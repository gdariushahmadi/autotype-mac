import SwiftUI
import AutoTypeCore

/// The menu behind the icon in the menu bar.
///
/// It is a real menu, so it behaves the way every other macOS menu behaves:
/// the rows are the right height, the separators are hairlines, the items
/// that are on carry a check mark, and the whole thing is keyboard
/// navigable.
///
/// The items live here directly rather than inside a `Menu` of their own: a
/// menu inside the menu bar icon would be shown as a single, nameless item.
struct MenuBarMenu: View {

    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        // The state of AutoType, shown as a heading. A disabled item is
        // the way a menu says “this is a label, not a button”.
        Button("AutoType (Beta) — \(status)") { }
            .disabled(true)

        Divider()

        Toggle("Convert Persian words", isOn: $model.settings.isEnabled)

        Divider()

        Picker("Typing mode", selection: $model.settings.mode) {
            Text("Automatic").tag(TypingMode.automatic)
            Text("Direct Persian").tag(TypingMode.directPersian)
        }
        .pickerStyle(.inline)

        Divider()

        Button("Settings…") {
            SystemActions.openSettingsWindow()
        }

        Divider()

        Button("Quit AutoType") {
            SystemActions.quit()
        }
    }

    /// One line that tells the user whether AutoType is doing anything.
    private var status: String {
        switch model.inputSourceStatus {
        case .enabled:
            return model.settings.isEnabled ? "Active" : "Turned off"
        case .installed:
            return "Not switched on"
        case .notInstalled:
            return "Not installed"
        case .unknown:
            return model.settings.isEnabled ? "Active" : "Turned off"
        }
    }
}
