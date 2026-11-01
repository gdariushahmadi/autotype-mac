import SwiftUI
import AutoTypeCore

/// The AI translation and custom action settings.
struct TranslationSettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showApiKey = false
    @State private var expandedActionIds: Set<UUID> = []

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    struct ActionPreset: Identifiable {
        let id = UUID()
        let title: String
        let trigger: String
        let position: TriggerPosition
        let prompt: String
    }

    private let presets: [ActionPreset] = [
        ActionPreset(
            title: "ترجمه (Translate)",
            trigger: "ترجمه",
            position: .either,
            prompt: TranslationSettings.defaultPrompt
        ),
        ActionPreset(
            title: "اصلاح و ویرایش (Proofread)",
            trigger: "اصلاح, ویرایش",
            position: .either,
            prompt: TranslationSettings.defaultProofreadPrompt
        ),
        ActionPreset(
            title: "خلاصه سازی (Summarize)",
            trigger: "خلاصه",
            position: .either,
            prompt: "You are an expert Persian summarizer. Provide a clear, concise, and structured summary of the given text in Persian. Output ONLY the summary without explanations or commentary."
        ),
        ActionPreset(
            title: "لحن اداری و محترمانه (Formal)",
            trigger: "رسمی, اداری",
            position: .either,
            prompt: "You are an expert in Persian professional communication. Rewrite the given Persian text in a polite, professional, and formal tone. Output ONLY the rewritten text without explanations."
        ),
        ActionPreset(
            title: "لحن دوستانه و صمیمی (Casual)",
            trigger: "دوستانه, صمیمی",
            position: .either,
            prompt: "You are an expert Persian writer. Rewrite the given Persian text in a friendly, warm, and natural conversational tone. Output ONLY the rewritten text without explanations."
        ),
        ActionPreset(
            title: "ترجمه به فارسی (To Persian)",
            trigger: "فارسی",
            position: .either,
            prompt: "You are a professional translator. Translate the given text into fluent, natural Persian. Output ONLY the translated text without explanations, quotes, or notes."
        ),
        ActionPreset(
            title: "ترجمه به عربی (To Arabic)",
            trigger: "عربی",
            position: .either,
            prompt: "You are a professional translator. Translate the given text into fluent, natural Arabic. Output ONLY the translated text without explanations, quotes, or notes."
        ),
        ActionPreset(
            title: "ترجمه به عبری (To Hebrew)",
            trigger: "عبری",
            position: .either,
            prompt: "You are a professional translator. Translate the given text into fluent, natural Hebrew. Output ONLY the translated text without explanations, quotes, or notes."
        ),
        ActionPreset(
            title: "ترجمه به آلمانی (To German)",
            trigger: "آلمانی, المانی",
            position: .either,
            prompt: "You are a professional translator. Translate the given text into fluent, natural German. Output ONLY the translated text without explanations, quotes, or notes."
        )
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Actions on Enter", isOn: $model.settings.translation.isEnabled)
                    .toggleStyle(.switch)
            } header: {
                Text("AI Assistant")
            } footer: {
                InlineHelp("Press Enter once to run the AI action (translation, proofreading, summarizing, tone adjustment, etc.), press Enter again to send it, or Esc to undo.")
            }

            actionsSection
                .disabled(!model.settings.translation.isEnabled)

            providerSection
                .disabled(!model.settings.translation.isEnabled)

            credentialsSection
                .disabled(!model.settings.translation.isEnabled)

            connectionSection
                .disabled(!model.settings.translation.isEnabled)
        }
        .formStyle(.grouped)
        .animation(.snappy(duration: 0.25), value: model.settings.translation.isEnabled)
        .onAppear {
            if expandedActionIds.isEmpty, let firstId = model.settings.translation.actions.first?.id {
                expandedActionIds.insert(firstId)
            }
        }
    }

    // MARK: - Actions & Prompts Section

    private var actionsSection: some View {
        Section {
            Toggle("Only trigger when a keyword is typed",
                   isOn: $model.settings.translation.requireTriggerPrefix)

            if model.settings.translation.requireTriggerPrefix {
                ForEach($model.settings.translation.actions) { $action in
                    actionCard(action: $action)
                }

                HStack {
                    Menu {
                        ForEach(presets) { preset in
                            Button(preset.title) {
                                addActionFromPreset(preset)
                            }
                        }
                        Divider()
                        Button("Custom Action…") {
                            addBlankAction()
                        }
                    } label: {
                        Label("Add Action", systemImage: "plus")
                    }

                    Spacer()

                    Button("Restore Defaults") {
                        restoreDefaultActions()
                    }
                    .buttonStyle(.link)
                }
                .padding(.top, 4)
            }
        } header: {
            HStack {
                Text("Actions & Prompts")
                Spacer()
                CountBadge(count: model.settings.translation.actions.count)
            }
        } footer: {
            InlineHelp("Configure multiple actions such as translation, proofreading, or custom prompts. Each action can trigger from the start or end of the sentence.")
        }
    }

    @ViewBuilder
    private func actionCard(action: Binding<AIAction>) -> some View {
        let isExpanded = expandedActionIds.contains(action.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("", isOn: action.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Text(action.wrappedValue.name.isEmpty ? "Action" : action.wrappedValue.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Position badge
                Text(action.wrappedValue.position.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                // Trigger pill
                Text(action.wrappedValue.trigger.isEmpty ? "No trigger" : action.wrappedValue.trigger)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isExpanded {
                            expandedActionIds.remove(action.id)
                        } else {
                            expandedActionIds.insert(action.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if model.settings.translation.actions.count > 1 {
                    Button(role: .destructive) {
                        deleteAction(id: action.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete this action")
                }
            }

            if isExpanded {
                Divider()
                    .padding(.vertical, 2)

                LabeledContent("Action Name") {
                    TextField("", text: action.name)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }

                LabeledContent("Trigger Keyword(s)") {
                    TextField("e.g. اصلاح, ویرایش, /fix", text: action.trigger)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }

                InlineHelp("Multiple keywords can be separated by commas. Typing on either English or Persian keyboard layout will automatically match.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Trigger Placement")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Trigger Placement", selection: action.position) {
                        ForEach(TriggerPosition.allCases, id: \.self) { pos in
                            Text(pos.displayName).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    InlineHelp(positionHelpText(for: action.wrappedValue))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("System Prompt")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    TextEditor(text: action.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 76)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func positionHelpText(for action: AIAction) -> String {
        let kw = action.trigger
            .components(separatedBy: CharacterSet(charactersIn: ",،;|\n"))
            .first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "کلید"

        switch action.position {
        case .start:
            return "Place the keyword at the start: «\(kw) متن شما»"
        case .end:
            return "Place the keyword at the end: «متن شما \(kw)»"
        case .either:
            return "Can be placed at the start («\(kw) متن شما») or at the end («متن شما \(kw)»)"
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
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
            InlineHelp("AutoType connects directly to MiniMax, Google Gemini, or any OpenAI-compatible endpoint.")
        }
    }

    // MARK: - Credentials Section

    private var credentialsSection: some View {
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
            InlineHelp("The API key stays stored locally on this Mac in ~/Library/Application Support/AutoType/settings.json.")
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
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
            InlineHelp("Sends a sample request to the configured AI provider to verify your API key and model.")
        }
    }

    // MARK: - Helpers

    private var apiKey: String {
        model.settings.translation.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func addActionFromPreset(_ preset: ActionPreset) {
        let action = AIAction(
            name: preset.title,
            trigger: preset.trigger,
            position: preset.position,
            systemPrompt: preset.prompt,
            isEnabled: true
        )
        model.settings.translation.actions.append(action)
        expandedActionIds.insert(action.id)
    }

    private func addBlankAction() {
        let action = AIAction(
            name: "New Action",
            trigger: "",
            position: .either,
            systemPrompt: "",
            isEnabled: true
        )
        model.settings.translation.actions.append(action)
        expandedActionIds.insert(action.id)
    }

    private func deleteAction(id: UUID) {
        guard model.settings.translation.actions.count > 1 else { return }
        model.settings.translation.actions.removeAll { $0.id == id }
        expandedActionIds.remove(id)
    }

    private func restoreDefaultActions() {
        model.settings.translation.actions = TranslationSettings.defaultActions
        if let firstId = model.settings.translation.actions.first?.id {
            expandedActionIds = [firstId]
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let testPrompt = model.settings.translation.actions.first(where: { $0.isEnabled })?.systemPrompt
                let response = try await TranslationService.shared.testConnection(
                    settings: model.settings.translation,
                    systemPrompt: testPrompt
                )
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
