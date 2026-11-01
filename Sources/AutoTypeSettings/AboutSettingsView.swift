import SwiftUI
import AppKit
import AutoTypeCore

/// The app itself: what it is, and the few things that belong to the system
/// rather than to a setting.
struct AboutSettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    AppIconView(size: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AutoType")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Persian input for macOS, without changing the keyboard layout.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Version \(Self.version)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }

            Section {
                Toggle("Open AutoType at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LaunchAtLogin.setEnabled(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }

                Button("Restart the input method") {
                    SystemActions.restartInputMethod()
                    model.refreshInputSourceStatus()
                }

                Button("Reveal the settings folder in Finder") {
                    SystemActions.revealSettingsFolder()
                }
            } header: {
                Text("System")
            } footer: {
                InlineHelp("The input method itself is started by macOS whenever a text field needs it, so it never needs a login item — only this window does.")
            }

            Section {
                Button("Quit AutoType", role: .destructive) {
                    SystemActions.quit()
                }
            } footer: {
                InlineHelp("AutoType keeps running in the menu bar until you quit it here.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    static var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
