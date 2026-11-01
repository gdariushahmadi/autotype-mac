import SwiftUI
import AutoTypeCore

/// The four AutoType actions that macOS offers as *Services*.
struct ServicesSettingsView: View {

    /// One of the four actions.
    private struct Action: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    private static let actions: [Action] = [
        Action(id: "convert",
               symbol: "character.book.closed",
               title: "Convert to Persian",
               detail: "Turns the selected Latin words into Persian — “sghl ;jhf” becomes “سلام کتاب”."),
        Action(id: "translate",
               symbol: "character.bubble",
               title: "Translate with AI",
               detail: "Translates the selection with the provider you configured in Translation."),
        Action(id: "dictionary",
               symbol: "text.badge.plus",
               title: "Add to Dictionary",
               detail: "Adds the selected word to your personal dictionary, so AutoType always treats it the same way."),
        Action(id: "latin",
               symbol: "character.cursor.ibeam",
               title: "Convert to Latin",
               detail: "Turns selected Persian back into the Latin keys that produce it — “سلام کتاب” becomes “sghl ;jhf”."),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.actions) { action in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.tint)
                            .frame(width: 20, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.body)
                            Text(action.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("AutoType actions")
            } footer: {
                InlineHelp("A service works on whatever text you have selected, in every app that has a Services menu.")
            }

            Section {
                Button("Open Services Settings") {
                    SystemActions.openServicesSettings()
                }
            } header: {
                Text("Turning them on")
            } footer: {
                InlineHelp("macOS keeps new services switched off until you allow them once, in Keyboard Settings → Keyboard Shortcuts → Services. After that they live in the Services menu of TextEdit, Notes, Mail, Safari and the other apps that have one — Chrome, VS Code and Slack do not have a Services menu.")
            }
        }
        .formStyle(.grouped)
    }
}
