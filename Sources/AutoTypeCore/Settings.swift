import Foundation

/// Everything the user can configure about how AutoType behaves.
public struct ConversionSettings: Codable, Equatable, Sendable {
    /// Whether automatic Persian/English typing conversion is enabled.
    public var isEnabled: Bool = true
    /// Automatic detection or direct Persian typing.
    public var mode: TypingMode = .automatic
    /// Which language wins for ambiguous words.
    public var priority: LanguagePriority = .automatic
    /// Smart contextual digits: English at start/English text, Persian digits inside Persian text.
    public var usePersianDigits: Bool = true
    /// Use `،` `؛` `؟` `٪` instead of their ASCII equivalents.
    public var usePersianPunctuation: Bool = true
    /// The key that types plain English while held down.
    public var englishModifier: EnglishModifier = .rightCommand
    /// Convert the selected text when the explicit command is used.
    public var convertSelection: Bool = true
    /// Show the typed word in a candidate window before committing it.
    public var showPreview: Bool = false
    /// Lock the rest of the sentence/line to the language detected on the first word.
    public var lockLanguageFromSentenceStart: Bool = true
    /// Automatically detect and fix transposed (swapped) characters when typing fast in Persian and English.
    public var fixTransposedCharacters: Bool = true
    /// Prevent accidental Enter dispatch if suspicious typos, broken words or grammar issues are detected.
    public var interceptSuspiciousEnter: Bool = true
    /// Prevent accidental Enter dispatch if sentence contains forbidden words.
    public var checkForForbiddenWords: Bool = true
    /// What to do when forbidden words are detected on Enter (require confirmation or block completely).
    public var forbiddenWordsAction: ForbiddenWordsAction = .requireConfirmation
    /// Automatic AI translation on Enter.
    public var translation: TranslationSettings = TranslationSettings()
    /// Bundle identifiers of applications where AutoType is disabled and passes all keys through.
    public var disabledApps: [String] = []

    public init() {}

    /// Reads the settings, falling back to the default for every key that is
    /// missing.
    ///
    /// A settings file written by an older version of AutoType — or edited by
    /// hand — must not wipe the user's configuration, so no key is required.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mode = try container.decodeIfPresent(TypingMode.self, forKey: .mode) ?? .automatic
        priority = try container.decodeIfPresent(LanguagePriority.self, forKey: .priority) ?? .automatic
        usePersianDigits = try container.decodeIfPresent(Bool.self, forKey: .usePersianDigits) ?? true
        usePersianPunctuation = try container.decodeIfPresent(Bool.self, forKey: .usePersianPunctuation) ?? true
        englishModifier = try container.decodeIfPresent(EnglishModifier.self, forKey: .englishModifier) ?? .rightCommand
        convertSelection = try container.decodeIfPresent(Bool.self, forKey: .convertSelection) ?? true
        showPreview = try container.decodeIfPresent(Bool.self, forKey: .showPreview) ?? false
        lockLanguageFromSentenceStart = try container.decodeIfPresent(Bool.self, forKey: .lockLanguageFromSentenceStart) ?? true
        fixTransposedCharacters = try container.decodeIfPresent(Bool.self, forKey: .fixTransposedCharacters) ?? true
        interceptSuspiciousEnter = try container.decodeIfPresent(Bool.self, forKey: .interceptSuspiciousEnter) ?? true
        checkForForbiddenWords = try container.decodeIfPresent(Bool.self, forKey: .checkForForbiddenWords) ?? true
        forbiddenWordsAction = try container.decodeIfPresent(ForbiddenWordsAction.self, forKey: .forbiddenWordsAction) ?? .requireConfirmation
        translation = try container.decodeIfPresent(TranslationSettings.self, forKey: .translation) ?? TranslationSettings()
        disabledApps = try container.decodeIfPresent([String].self, forKey: .disabledApps) ?? []
    }

    public init(
        isEnabled: Bool = true,
        mode: TypingMode = .automatic,
        priority: LanguagePriority = .automatic,
        usePersianDigits: Bool = true,
        usePersianPunctuation: Bool = true,
        englishModifier: EnglishModifier = .rightCommand,
        convertSelection: Bool = true,
        showPreview: Bool = false,
        lockLanguageFromSentenceStart: Bool = true,
        fixTransposedCharacters: Bool = true,
        interceptSuspiciousEnter: Bool = true,
        checkForForbiddenWords: Bool = true,
        forbiddenWordsAction: ForbiddenWordsAction = .requireConfirmation,
        translation: TranslationSettings = TranslationSettings(),
        disabledApps: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.priority = priority
        self.usePersianDigits = usePersianDigits
        self.usePersianPunctuation = usePersianPunctuation
        self.englishModifier = englishModifier
        self.convertSelection = convertSelection
        self.showPreview = showPreview
        self.lockLanguageFromSentenceStart = lockLanguageFromSentenceStart
        self.fixTransposedCharacters = fixTransposedCharacters
        self.interceptSuspiciousEnter = interceptSuspiciousEnter
        self.checkForForbiddenWords = checkForForbiddenWords
        self.forbiddenWordsAction = forbiddenWordsAction
        self.translation = translation
        self.disabledApps = disabledApps
    }

    /// `true` when the application with the given bundle identifier is in the disabled apps list.
    public func isAppDisabled(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        let lower = bundleID.lowercased()
        return disabledApps.contains { $0.lowercased() == lower }
    }
}

/// Action to take when a sentence contains forbidden words upon pressing Enter.
public enum ForbiddenWordsAction: String, Codable, CaseIterable, Sendable {
    /// Require a second Enter press to confirm sending.
    case requireConfirmation = "requireConfirmation"
    /// Prevent sending completely (Enter is ignored and beep alert is played).
    case block = "block"

    public var displayName: String {
        switch self {
        case .requireConfirmation: return "نیاز به تایید با فشردن مجدد اینتر (Require 2nd Enter)"
        case .block: return "جلوگیری کامل از ارسال (Block completely)"
        }
    }
}

/// Supported AI providers for automatic translation.
public enum TranslationProvider: String, Codable, CaseIterable, Sendable {
    case minimax = "minimax"
    case gemini = "gemini"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .minimax: return "MiniMax"
        case .gemini: return "Google Gemini"
        case .custom: return "Custom / OpenAI"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .minimax:
            return "https://api.minimax.io/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .custom:
            return "https://api.openai.com/v1/chat/completions"
        }
    }

    public var defaultModel: String {
        switch self {
        case .minimax: return "MiniMax-Text-01"
        case .gemini: return "gemini-1.5-flash"
        case .custom: return "gpt-4o-mini"
        }
    }
}

/// Where the trigger keyword must be positioned in the sentence.
public enum TriggerPosition: String, Codable, CaseIterable, Sendable {
    case start = "start"
    case end = "end"
    case either = "either"

    public var displayName: String {
        switch self {
        case .start: return "ابتدای جمله (Start)"
        case .end: return "انتهای جمله (End)"
        case .either: return "ابتدا یا انتها (Start or End)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .start: return "ابتدا"
        case .end: return "انتها"
        case .either: return "ابتدا یا انتها"
        }
    }
}

/// A custom AI action triggered on Enter by specific keywords and configured with a prompt.
public struct AIAction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: String
    public var position: TriggerPosition
    public var systemPrompt: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: String,
        position: TriggerPosition = .either,
        systemPrompt: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.position = position
        self.systemPrompt = systemPrompt
        self.isEnabled = isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Action"
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        position = try container.decodeIfPresent(TriggerPosition.self, forKey: .position) ?? .either
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// The result of extracting an AI action and the clean body text from a line.
public struct ExtractionResult: Equatable, Sendable {
    public let body: String
    public let action: AIAction
    public let matchedTrigger: String
    public let position: TriggerPosition

    public init(body: String, action: AIAction, matchedTrigger: String, position: TriggerPosition) {
        self.body = body
        self.action = action
        self.matchedTrigger = matchedTrigger
        self.position = position
    }
}

/// Settings for AI translation and actions on Enter.
public struct TranslationSettings: Codable, Equatable, Sendable {
    public static let defaultPrompt = "You are a professional translator. Translate the given Persian text into fluent, natural English. Output ONLY the translated text without explanations, quotes, or notes."

    public static let defaultProofreadPrompt = "You are an expert Persian editor. Proofread and correct the given text for spelling errors, typography, half-spaces (نیم‌فاصله), and grammar. Keep the tone natural and meaning intact. Output ONLY the corrected text without explanations, notes, or quotation marks."

    public static var defaultActions: [AIAction] {
        [
            AIAction(
                name: "ترجمه (Translate)",
                trigger: "ترجمه",
                position: .either,
                systemPrompt: defaultPrompt,
                isEnabled: true
            ),
            AIAction(
                name: "اصلاح و ویرایش (Proofread)",
                trigger: "اصلاح, ویرایش",
                position: .either,
                systemPrompt: defaultProofreadPrompt,
                isEnabled: true
            ),
            AIAction(
                name: "خلاصه سازی (Summarize)",
                trigger: "خلاصه",
                position: .either,
                systemPrompt: "You are an expert Persian summarizer. Provide a clear, concise, and structured summary of the given text in Persian. Output ONLY the summary without explanations or commentary.",
                isEnabled: true
            ),
            AIAction(
                name: "لحن اداری و رسمی (Formal)",
                trigger: "رسمی, اداری",
                position: .either,
                systemPrompt: "You are an expert in Persian professional communication. Rewrite the given Persian text in a polite, professional, and formal tone. Output ONLY the rewritten text without explanations.",
                isEnabled: true
            ),
            AIAction(
                name: "لحن دوستانه و صمیمی (Casual)",
                trigger: "دوستانه, صمیمی",
                position: .either,
                systemPrompt: "You are an expert Persian writer. Rewrite the given Persian text in a friendly, warm, and natural conversational tone. Output ONLY the rewritten text without explanations.",
                isEnabled: true
            )
        ]
    }

    public var isEnabled: Bool = false
    public var requireTriggerPrefix: Bool = true
    public var triggerPrefix: String = "ترجمه" {
        didSet {
            // Keep first action trigger in sync if updated
            if !actions.isEmpty && actions[0].name.contains("ترجمه") {
                actions[0].trigger = triggerPrefix
            }
        }
    }
    public var actions: [AIAction] = TranslationSettings.defaultActions
    public var provider: TranslationProvider = .minimax
    public var endpoint: String = TranslationProvider.minimax.defaultEndpoint
    public var apiKey: String = ""
    public var model: String = TranslationProvider.minimax.defaultModel
    public var systemPrompt: String = TranslationSettings.defaultPrompt {
        didSet {
            // Keep first action systemPrompt in sync if updated
            if !actions.isEmpty && actions[0].name.contains("ترجمه") {
                actions[0].systemPrompt = systemPrompt
            }
        }
    }

    public init() {}

    public init(
        isEnabled: Bool = false,
        requireTriggerPrefix: Bool = true,
        triggerPrefix: String = "ترجمه",
        actions: [AIAction] = TranslationSettings.defaultActions,
        provider: TranslationProvider = .minimax,
        endpoint: String = TranslationProvider.minimax.defaultEndpoint,
        apiKey: String = "",
        model: String = TranslationProvider.minimax.defaultModel,
        systemPrompt: String = TranslationSettings.defaultPrompt
    ) {
        self.isEnabled = isEnabled
        self.requireTriggerPrefix = requireTriggerPrefix
        self.triggerPrefix = triggerPrefix
        self.actions = actions
        self.provider = provider
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        requireTriggerPrefix = try container.decodeIfPresent(Bool.self, forKey: .requireTriggerPrefix) ?? true
        triggerPrefix = try container.decodeIfPresent(String.self, forKey: .triggerPrefix) ?? "ترجمه"
        provider = try container.decodeIfPresent(TranslationProvider.self, forKey: .provider) ?? .minimax
        let rawEndpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? provider.defaultEndpoint
        if rawEndpoint == "https://api.minimax.chat/v1/text/chatcompletion_v2" {
            endpoint = TranslationProvider.minimax.defaultEndpoint
        } else {
            endpoint = rawEndpoint
        }
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? provider.defaultModel
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? TranslationSettings.defaultPrompt

        if let decodedActions = try container.decodeIfPresent([AIAction].self, forKey: .actions), !decodedActions.isEmpty {
            actions = decodedActions
        } else {
            var defaults = TranslationSettings.defaultActions
            if triggerPrefix != "ترجمه" || systemPrompt != TranslationSettings.defaultPrompt {
                defaults[0].trigger = triggerPrefix
                defaults[0].systemPrompt = systemPrompt
            }
            actions = defaults
        }
    }

    /// Checks whether `line` matches an active AI action based on configured keywords and position (start, end, or either).
    /// Returns the extraction result (cleaned body, matched action, trigger, and position), or `nil` if not applicable.
    public func extractActionAndBody(from line: String) -> ExtractionResult? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let activeActions = actions.filter { $0.isEnabled }

        guard requireTriggerPrefix else {
            // When trigger keywords are not required, run the first enabled action on Persian text
            guard let firstAction = activeActions.first else { return nil }
            return PersianText.containsPersian(trimmed)
                ? ExtractionResult(body: trimmed, action: firstAction, matchedTrigger: "", position: .start)
                : nil
        }

        guard !activeActions.isEmpty else { return nil }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：-—،,;؛|"))

        for action in activeActions {
            let rawTriggers = action.trigger
                .components(separatedBy: CharacterSet(charactersIn: ",،;|\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !rawTriggers.isEmpty else { continue }

            var prefixes: [String] = []
            for p in rawTriggers {
                if !prefixes.contains(p) { prefixes.append(p) }
                if let converted = PersianLayout.convert(p), !prefixes.contains(converted) {
                    prefixes.append(converted)
                }
                if let latin = PersianLayout.convertToLatin(p), !prefixes.contains(latin) {
                    prefixes.append(latin)
                }
            }

            // Keyboard aliases for well-known triggers
            for p in rawTriggers {
                if p == "ترجمه" {
                    for alias in ["jv[li", "/tr", "tr:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "اصلاح" {
                    for alias in ["hwghp", "/fix", "fix:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "ویرایش" {
                    for alias in [",dvhda", "/edit", "edit:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "خلاصه" {
                    for alias in ["oghwi", "/sum", "sum:", "/summary"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "رسمی" {
                    for alias in ["vsld", "/formal", "formal:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "اداری" {
                    for alias in ["hnhvd", "/formal"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "دوستانه" {
                    for alias in ["n,sjhik", "/casual", "casual:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "عربی" {
                    for alias in ["uvfd", "/ar", "ar:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "عبری" {
                    for alias in ["ufvd", "/he", "he:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                } else if p == "آلمانی" || p == "المانی" {
                    for alias in ["Hglhkd", "hglhkd", "/de", "de:"] where !prefixes.contains(alias) {
                        prefixes.append(alias)
                    }
                }
            }

            // Prefer longer triggers first
            prefixes.sort { $0.count > $1.count }

            let canCheckStart = (action.position == .start || action.position == .either)
            let canCheckEnd = (action.position == .end || action.position == .either)

            // 1) Check Start of sentence
            if canCheckStart {
                for trigger in prefixes {
                    let lowerTrimmed = trimmed.lowercased()
                    let lowerTrigger = trigger.lowercased()
                    if lowerTrimmed.hasPrefix(lowerTrigger) {
                        let afterIndex = trimmed.index(trimmed.startIndex, offsetBy: trigger.count)
                        if afterIndex < trimmed.endIndex {
                            let nextChar = trimmed[afterIndex]
                            guard nextChar.unicodeScalars.allSatisfy({ separators.contains($0) }) else {
                                continue
                            }
                        }
                        let remainder = trimmed[afterIndex...].trimmingCharacters(in: separators)
                        guard !remainder.isEmpty else { continue }
                        return ExtractionResult(
                            body: remainder,
                            action: action,
                            matchedTrigger: trigger,
                            position: .start
                        )
                    }
                }
            }

            // 2) Check End of sentence
            if canCheckEnd {
                for trigger in prefixes {
                    let lowerTrimmed = trimmed.lowercased()
                    let lowerTrigger = trigger.lowercased()
                    if lowerTrimmed.hasSuffix(lowerTrigger) {
                        let beforeIndex = trimmed.index(trimmed.endIndex, offsetBy: -trigger.count)
                        if beforeIndex > trimmed.startIndex {
                            let prevChar = trimmed[trimmed.index(before: beforeIndex)]
                            guard prevChar.unicodeScalars.allSatisfy({ separators.contains($0) }) else {
                                continue
                            }
                        }
                        let remainder = trimmed[..<beforeIndex].trimmingCharacters(in: separators)
                        guard !remainder.isEmpty else { continue }
                        return ExtractionResult(
                            body: remainder,
                            action: action,
                            matchedTrigger: trigger,
                            position: .end
                        )
                    }
                }
            }
        }

        return nil
    }

    /// Backward-compatible extraction: returns the cleaned body text to translate, or `nil`.
    public func extractTranslatableBody(from line: String) -> String? {
        return extractActionAndBody(from: line)?.body
    }
}

/// The user's own dictionary: Persian words that must always convert, and
/// English words that must never convert, plus forbidden words.
public struct PersonalDictionary: Codable, Equatable, Sendable {
    public var persianWords: [String] = []
    public var englishWords: [String] = []
    public var forbiddenWords: [String] = []

    public init(
        persianWords: [String] = [],
        englishWords: [String] = [],
        forbiddenWords: [String] = []
    ) {
        self.persianWords = persianWords
        self.englishWords = englishWords
        self.forbiddenWords = forbiddenWords
    }

    /// Reads the dictionary, ignoring keys that are missing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        persianWords = try container.decodeIfPresent([String].self, forKey: .persianWords) ?? []
        englishWords = try container.decodeIfPresent([String].self, forKey: .englishWords) ?? []
        forbiddenWords = try container.decodeIfPresent([String].self, forKey: .forbiddenWords) ?? []
    }
}

/// Reads and writes the shared configuration.
///
/// The input method and the settings app are separate processes, so the
/// configuration lives in a file under Application Support rather than in
/// `UserDefaults` (which would need a shared app group to work for both).
public final class SettingsStore {

    public static let shared = SettingsStore()

    /// The directory holding AutoType's shared state.
    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AutoType", isDirectory: true)
    }

    public static var settingsURL: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    public static var dictionaryURL: URL {
        applicationSupportDirectory.appendingPathComponent("dictionary.json")
    }

    private let queue = DispatchQueue(label: "digital.autotype.settings", attributes: .concurrent)

    private var cachedSettings: ConversionSettings?
    private var cachedDictionary: PersonalDictionary?

    public init() {}

    // MARK: - Settings

    /// The current settings, reading from disk the first time.
    public var settings: ConversionSettings {
        queue.sync {
            if let cachedSettings { return cachedSettings }
            let loaded = Self.readSettings()
            cachedSettings = loaded
            return loaded
        }
    }

    /// Writes the settings and refreshes the cache.
    public func save(_ settings: ConversionSettings) {
        queue.sync(flags: .barrier) {
            do {
                try FileManager.default.createDirectory(
                    at: Self.applicationSupportDirectory,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(settings).write(to: Self.settingsURL, options: .atomic)
                cachedSettings = settings
            } catch {
                NSLog("AutoType: could not save settings: \(error.localizedDescription)")
            }
        }
    }

    /// Re-reads the settings from disk, so a change made in the settings app
    /// is picked up by the input method.
    @discardableResult
    public func reload() -> ConversionSettings {
        queue.sync(flags: .barrier) {
            let loaded = Self.readSettings()
            cachedSettings = loaded
            return loaded
        }
    }

    private static func readSettings() -> ConversionSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(ConversionSettings.self, from: data) else {
            return ConversionSettings()
        }
        return decoded
    }

    // MARK: - Personal dictionary

    public var dictionary: PersonalDictionary {
        queue.sync {
            if let cachedDictionary { return cachedDictionary }
            let loaded = Self.readDictionary()
            cachedDictionary = loaded
            return loaded
        }
    }

    public func save(_ dictionary: PersonalDictionary) {
        queue.sync(flags: .barrier) {
            do {
                try FileManager.default.createDirectory(
                    at: Self.applicationSupportDirectory,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(dictionary).write(to: Self.dictionaryURL, options: .atomic)
                cachedDictionary = dictionary
            } catch {
                NSLog("AutoType: could not save dictionary: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    public func reloadDictionary() -> PersonalDictionary {
        queue.sync(flags: .barrier) {
            let loaded = Self.readDictionary()
            cachedDictionary = loaded
            return loaded
        }
    }

    private static func readDictionary() -> PersonalDictionary {
        guard let data = try? Data(contentsOf: dictionaryURL),
              let decoded = try? JSONDecoder().decode(PersonalDictionary.self, from: data) else {
            return PersonalDictionary()
        }
        return decoded
    }
}
