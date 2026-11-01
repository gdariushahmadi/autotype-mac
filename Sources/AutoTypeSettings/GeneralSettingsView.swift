import SwiftUI
import AppKit
import AutoTypeCore

/// Everything about how AutoType decides what a word is.
struct GeneralSettingsView: View {

    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        Form {
            // The state of the input method. It sits in a group of its own,
            // so the window says straight away whether AutoType is running.
            Section {
                StatusCard(status: model.inputSourceStatus) {
                    model.refreshInputSourceStatus()
                }
            }

            Section {
                Toggle("Convert Persian words automatically", isOn: $model.settings.isEnabled)
                    .toggleStyle(.switch)
            } header: {
                Text("AutoType")
            } footer: {
                InlineHelp("You keep the English layout and AutoType turns the Persian words into Persian. When this is off, every key types a Persian letter — a plain Persian keyboard.")
            }

            if model.settings.isEnabled {
                Section {
                    Picker("Typing mode", selection: $model.settings.mode) {
                        Text("Automatic").tag(TypingMode.automatic)
                        Text("Direct Persian").tag(TypingMode.directPersian)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Typing mode")
                } header: {
                    Text("Typing mode")
                } footer: {
                    InlineHelp(modeExplanation)
                }

                Section {
                    Toggle("Lock the language to the first word of the sentence",
                           isOn: $model.settings.lockLanguageFromSentenceStart)

                    Picker("Priority", selection: $model.settings.priority) {
                        Text("Automatic").tag(LanguagePriority.automatic)
                        Text("Persian").tag(LanguagePriority.persianFirst)
                        Text("English").tag(LanguagePriority.englishFirst)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Priority for ambiguous words")
                } header: {
                    Text("Ambiguous words")
                } footer: {
                    InlineHelp("Some words can be read as Persian or as English. AutoType decides from the sentence around the word, or with the rule you pick here.")
                }

                Section {
                    Picker("Hold to type plain English", selection: $model.settings.englishModifier) {
                        ForEach(EnglishModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                } header: {
                    Text("Typing English")
                } footer: {
                    InlineHelp("Hold this key while you type to get plain English, with no conversion at all.")
                }

                Section {
                    Toggle("Persian numerals ۱۲۳", isOn: $model.settings.usePersianDigits)
                    Toggle("Persian punctuation ، ؛ ؟ ٪", isOn: $model.settings.usePersianPunctuation)
                } header: {
                    Text("Persian text")
                } footer: {
                    InlineHelp("Numbers and punctuation inside a Persian sentence are written the Persian way.")
                }
            }
        }
        .formStyle(.grouped)
        .animation(.snappy(duration: 0.25), value: model.settings.isEnabled)
    }

    private var modeExplanation: String {
        switch model.settings.mode {
        case .automatic:
            return "English words stay exactly as you type them, and Persian words are converted as soon as you finish the word."
        case .directPersian:
            return "Every key produces its Persian letter straight away — the same as a Persian keyboard layout."
        }
    }
}

// MARK: - Status

/// The state of the input method, at the top of the general settings.
struct StatusCard: View {

    let status: InputSourceStatus
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(status.tint)
                .frame(width: 34, height: 34)
                .background(status.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline)
                Text(status.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if !status.isUsable {
                    Button("Open Keyboard Settings…") {
                        SystemActions.openKeyboardSettings()
                    }
                    .controlSize(.small)
                }

                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Check again")
            }
        }
        .padding(.vertical, 4)
    }
}
