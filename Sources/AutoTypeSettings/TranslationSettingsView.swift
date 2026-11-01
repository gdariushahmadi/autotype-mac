import SwiftUI
import AutoTypeCore

/// The AI translation that happens when Enter is pressed.
struct TranslationSettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showApiKey = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Translate on Enter", isOn: $model.settings.translation.isEnabled)
                    .toggleStyle(.switch)
            } header: {
                Text("Translation")
            } footer: {
                InlineHelp("Press Enter once to translate the Persian sentence, press Enter again to send it.")
            }

            if model.settings.translation.isEnabled {
                Section {
                    Toggle("Only translate sentences that start with a keyword",
                           isOn: $model.settings.translation.requireTriggerPrefix)

                    if model.settings.translation.requireTriggerPrefix {
                        LabeledContent("Keyword") {
                            // The field has no title of its own: the row already
                            // says what the field is.
                            TextField("", text: $model.settings.translation.triggerPrefix)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .multilineTextAlignment(.leading)
                        }
                    }
                } header: {
                    Text("Trigger")
                } footer: {
                    InlineHelp(triggerExplanation)
                }

                Section {
                    Picker("Service", selection: $model.settings.translation.provider) {
                        ForEach(TranslationProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Translation service")
                    .onChange(of: model.settings.translation.provider) { _, newProvider in
                        model.settings.translation.endpoint = newProvider.defaultEndpoint
                        model.settings.translation.model = newProvider.defaultModel
                        testResult = nil
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    InlineHelp("AutoType talks to the provider in the same way any chat client does, so any service that speaks the OpenAI format works.")
                }

                Section {
                    HStack(spacing: 8) {
                        Group {
                            if showApiKey {
                                TextField("API key", text: $model.settings.translation.apiKey)
                            } else {
                                SecureField("API key", text: $model.settings.translation.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(showApiKey ? "Hide the key" : "Show the key")
                    }

                    LabeledContent("Model") {
                        TextField("", text: $model.settings.translation.model)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                    }

                    LabeledContent("Endpoint") {
                        TextField("", text: $model.settings.translation.endpoint)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                    }
                } header: {
                    Text("Request")
                } footer: {
                    InlineHelp("The key never leaves this Mac: it is stored in ~/Library/Application Support/AutoType/settings.json.")
                }

                Section {
                    TextEditor(text: $model.settings.translation.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 84)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    Button("Restore the default prompt") {
                        model.settings.translation.systemPrompt = TranslationSettings.defaultPrompt
                    }
                    .buttonStyle(.link)
                } header: {
                    Text("System prompt")
                } footer: {
                    InlineHelp("The instructions the model is given before it translates. The default asks for a natural English translation and nothing else.")
                }

                Section {
                    HStack(spacing: 10) {
                        Button(action: runTest) {
                            if isTesting {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Testing…")
                                }
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTesting || apiKey.isEmpty)

                        Spacer(minLength: 8)

                        if let testResult {
                            testResultView(testResult)
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    InlineHelp("Sends a short sentence to the provider with the current settings, so you can check the key and the model before you rely on them.")
                }
            }
        }
        .formStyle(.grouped)
        .animation(.snappy(duration: 0.25), value: model.settings.translation.isEnabled)
    }

    // MARK: - Pieces

    private var apiKey: String {
        model.settings.translation.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var triggerExplanation: String {
        let keyword = model.settings.translation.triggerPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return "Only sentences that start with the keyword are translated. Several keywords can be separated with a comma."
        }
        return "Type «\(keyword) سلام چطوری» and press Enter: only the part after the keyword is translated. Several keywords can be separated with a comma."
    }

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let output):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("“\(output)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help("The provider answered with “\(output)”.")
        case .failure(let message):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .help(message)
        }
    }

    // MARK: - Testing

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let response = try await TranslationService.shared.testConnection(settings: model.settings.translation)
                await MainActor.run {
                    self.testResult = .success(response)
                    self.isTesting = false
                }
            } catch {
                await MainActor.run {
                    self.testResult = .failure(error.localizedDescription)
                    self.isTesting = false
                }
            }
        }
    }
}
