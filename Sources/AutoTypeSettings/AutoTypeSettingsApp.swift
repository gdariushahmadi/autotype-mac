import SwiftUI
import AutoTypeCore

@main
struct AutoTypeSettingsApp: App {

    @StateObject private var model = SettingsModel()

    var body: some Scene {
        MenuBarExtra {
            SettingsView()
                .environmentObject(model)
                .frame(width: 420)
        } label: {
            Image(systemName: model.settings.mode == .directPersian
                  ? "character.bubble.fill"
                  : "character.book.closed")
                .accessibilityLabel("AutoType")
        }
        .menuBarExtraStyle(.window)
    }
}
