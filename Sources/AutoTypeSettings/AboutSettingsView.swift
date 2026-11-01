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
                        HStack(spacing: 8) {
                            Text("AutoType")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("BETA")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                        Text("Persian input for macOS, without changing the keyboard layout.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Version \(Self.version) — Beta Release (نسخهٔ آزمایشی بتا)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Beta Release Notice (نسخهٔ آزمایشی بتا)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("AutoType is currently in Beta. If you notice unexpected behavior in a specific app or with certain words, you can hold Right ⌘ to type plain English, add words to your Dictionary, or disable AutoType for specific apps in the Excluded Apps tab.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
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
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Origin & Inspiration (ایدهٔ اولیه)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("ایدهٔ اولیهٔ این برنامه از دیار (Diyar) و توییت معرفی آن شروع شد؛ بعد از ساخت نسخهٔ مک، کنترل روی ورودی سیستم‌عامل باعث شد امکانات کاربردی زیادی برای استفادهٔ روزمره به آن اضافه شود.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: "https://diyar.digital/fa/") {
                            Link("diyar.digital/fa ↗", destination: url)
                                .font(.caption)
                                .padding(.top, 2)
                        }
                    }
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.blue)
                }
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
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0-beta"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
