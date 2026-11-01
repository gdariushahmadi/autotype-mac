import SwiftUI
import AutoTypeCore

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
                Toggle("Translate on Enter (ترجمه با Enter)", isOn: $model.settings.translation.isEnabled)
                Text("Press Enter once to translate Persian to English. Press Enter again to send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.settings.translation.isEnabled {
                Section("Trigger Keyword (کلمهٔ شروع ترجمه)") {
                    Toggle("Only translate when sentence starts with keyword", isOn: $model.settings.translation.requireTriggerPrefix)
                    if model.settings.translation.requireTriggerPrefix {
                        TextField("Trigger Keyword (e.g. ترجمه)", text: $model.settings.translation.triggerPrefix)
                            .textFieldStyle(.roundedBorder)
                        Text("Example: type «\(model.settings.translation.triggerPrefix.isEmpty ? "ترجمه" : model.settings.translation.triggerPrefix) سلام چطوری» and press Enter. Only the sentence after the keyword is translated.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Provider") {
                    Picker("Service", selection: $model.settings.translation.provider) {
                        ForEach(TranslationProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.settings.translation.provider) { _, newProvider in
                        model.settings.translation.endpoint = newProvider.defaultEndpoint
                        model.settings.translation.model = newProvider.defaultModel
                        testResult = nil
                    }
                }

                Section("API Configuration") {
                    HStack {
                        if showApiKey {
                            TextField("API Key", text: $model.settings.translation.apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $model.settings.translation.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showApiKey.toggle() }) {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Endpoint URL", text: $model.settings.translation.endpoint)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model Name", text: $model.settings.translation.model)
                        .textFieldStyle(.roundedBorder)
                }

                Section("System Prompt") {
                    TextEditor(text: $model.settings.translation.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 55)

                    Button("Reset to Default Prompt") {
                        model.settings.translation.systemPrompt = TranslationSettings.defaultPrompt
                    }
                    .font(.caption)
                }

                Section {
                    HStack {
                        Button(action: runTest) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                        .disabled(isTesting || model.settings.translation.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()

                        if let testResult {
                            switch testResult {
                            case .success(let output):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Success: \"\(output)\"")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            case .failure(let errorMsg):
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(errorMsg)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

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
