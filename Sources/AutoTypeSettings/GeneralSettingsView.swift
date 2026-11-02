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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flask.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Beta Version (نسخهٔ آزمایشی بتا)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                        Text("This version is in active beta testing. Please keep an eye on conversions; you can exclude specific apps in Excluded Apps or hold Right ⌘ anytime for plain English.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
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
                    Label {
                        Text("The first word of a sentence decides its language: a Persian sentence stays Persian, an English one stays English. A word that has no equivalent in the other language — «از», «در», «یا» — is always Persian, and a word that only exists in English stays English inside a Persian sentence.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                }

                Section {
                    Picker("Default typing language", selection: $model.settings.defaultLanguage) {
                        ForEach(DefaultLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    Picker("Language switch shortcut", selection: $model.settings.englishModifier) {
                        ForEach(EnglishModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                } header: {
                    Text("Language & Typing (زبان و تایپ)")
                } footer: {
                    InlineHelp("When default is Persian, the shortcut switches to English. When default is English, the shortcut switches to Persian. With Caps Lock, pressing the Caps Lock key toggles between Persian and English.")
                }

                Section {
                    Toggle("Smart numbers (۱۲۳ in Persian, 123 at start)", isOn: $model.settings.usePersianDigits)
                    Toggle("Persian punctuation ، ؛ ؟ ٪", isOn: $model.settings.usePersianPunctuation)
                    Toggle("Fix spaces around punctuation", isOn: $model.settings.fixPunctuationSpacing)
                } header: {
                    Text("Persian text")
                } footer: {
                    InlineHelp("When starting or in English, numbers are typed as 123. Inside Persian text, numbers match the language (۱۲۳).")
                }

                Section {
                    Toggle("Fix transposed characters automatically (اصلاح جابجایی حروف)",
                           isOn: $model.settings.fixTransposedCharacters)
                } header: {
                    Text("Smart Typo Correction (اصلاح هوشمند جابجایی حروف)")
                } footer: {
                    InlineHelp("Automatically detects and fixes accidentally swapped characters when typing fast in Persian and English (e.g. «انلگیسی» → «انگلیسی», «برنماه» → «برنامه», «teh» → «the», «recieve» → «receive»).")
                }

                Section {
                    Toggle("Prevent accidental sending of forbidden words",
                           isOn: $model.settings.checkForForbiddenWords)

                    if model.settings.checkForForbiddenWords {
                        Picker("When forbidden words are found", selection: $model.settings.forbiddenWordsAction) {
                            Text("Require 2nd Enter to confirm").tag(ForbiddenWordsAction.requireConfirmation)
                            Text("Block sending completely").tag(ForbiddenWordsAction.block)
                        }

                        LabeledContent("Configured forbidden words") {
                            Text("\(model.dictionary.forbiddenWords.count) words in Dictionary")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Send Protection (جلوگیری از ارسال ناخواسته)")
                } footer: {
                    InlineHelp("Intercepts the Enter key when the typed sentence contains forbidden words. You can manage the forbidden words list in the Dictionary tab.")
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
