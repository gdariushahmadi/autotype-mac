import SwiftUI
import AppKit
import AutoTypeCore

struct SettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var selectedTab = Tab.general

    enum Tab: Hashable {
        case general
        case dictionary
        case translation
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("AutoType Settings")
                    .font(.headline)
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("خروج کامل (Quit)", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            TabView(selection: $selectedTab) {
                GeneralView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(Tab.general)

                DictionaryView()
                    .tabItem { Label("Dictionary", systemImage: "text.book.closed") }
                    .tag(Tab.dictionary)

                TranslationSettingsView()
                    .tabItem { Label("Translation", systemImage: "character.bubble") }
                    .tag(Tab.translation)
            }
            .frame(height: 520)
        }
        .frame(width: 440)
    }
}

// MARK: - General

struct GeneralView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                StatusRow(status: model.inputSourceStatus) {
                    model.refreshInputSourceStatus()
                }
            }

            Section("AutoType") {
                Toggle("Enable AutoType (تشخیص خودکار فارسی و انگلیسی)", isOn: $model.settings.isEnabled)
                Text("وقتی تیک نخورده باشد، کیبورد مستقیماً فارسی تایپ می‌کند. با زدن تیک، کلمات انگلیسی و فارسی هوشمند تشخیص داده می‌شوند.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.settings.isEnabled {
                Section("Typing") {
                    Picker("Mode", selection: $model.settings.mode) {
                        Text("Detect Persian automatically").tag(TypingMode.automatic)
                        Text("Always type Persian").tag(TypingMode.directPersian)
                    }
                    .pickerStyle(.radioGroup)

                    Text(model.settings.mode == .automatic
                         ? "English words stay as they are; Persian words are converted when you finish the word."
                         : "Every key produces its Persian letter straight away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Ambiguous words") {
                    Toggle("تشخیص هوشمند زبان از کلمهٔ شروع جمله", isOn: $model.settings.lockLanguageFromSentenceStart)
                    Text("اگر کلمه اول جمله فارسی باشد، بقیهٔ کلمات آن جمله ترجیحاً فارسی می‌شوند؛ و اگر با انگلیسی شروع شود، بقیهٔ جمله انگلیسی خواهد ماند.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("When a word could be either", selection: $model.settings.priority) {
                        Text("Use the surrounding text").tag(LanguagePriority.automatic)
                        Text("Prefer Persian").tag(LanguagePriority.persianFirst)
                        Text("Prefer English").tag(LanguagePriority.englishFirst)
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Typing English") {
                    Picker("Hold this key to type plain English", selection: $model.settings.englishModifier) {
                        ForEach(EnglishModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                }

                Section("Persian text") {
                    Toggle("Persian numerals ۱۲۳", isOn: $model.settings.usePersianDigits)
                    Toggle("Persian punctuation ، ؛ ؟ ٪", isOn: $model.settings.usePersianPunctuation)
                }
            }

            Section("System") {
                Toggle("Open AutoType at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LaunchAtLogin.setEnabled(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            Section {
                HStack {
                    Button("Open Keyboard Settings") { openKeyboardSettings() }
                    Spacer()
                    Text("AutoType \(Self.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Restart Input Method") {
                        let task = Process()
                        task.launchPath = "/usr/bin/killall"
                        task.arguments = ["AutoTypeIME"]
                        try? task.run()
                        model.refreshInputSourceStatus()
                    }
                    Spacer()
                    Button("Quit AutoType Settings", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.reload()
            model.refreshInputSourceStatus()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    static var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func openKeyboardSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?TextInput",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Status

struct StatusRow: View {

    let status: InputSourceStatus
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: status.isUsable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isUsable ? Color.green : Color.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.headline)
                if !status.isUsable {
                    Text("Open Keyboard Settings → Text Input → Edit, then add AutoType.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check again")
        }
        .padding(.vertical, 2)
    }
}
