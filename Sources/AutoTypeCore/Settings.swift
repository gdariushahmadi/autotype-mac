import Foundation

/// Everything the user can configure about how AutoType behaves.
public struct ConversionSettings: Codable, Equatable, Sendable {
    /// Whether automatic Persian/English typing conversion is enabled.
    public var isEnabled: Bool = true
    /// Automatic detection or direct Persian typing.
    public var mode: TypingMode = .automatic
    /// Which language wins for ambiguous words.
    public var priority: LanguagePriority = .automatic
    /// Convert digits inside Persian sentences to Persian numerals.
    public var usePersianDigits: Bool = false
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
    /// Prevent accidental Enter dispatch if suspicious typos, broken words or grammar issues are detected.
    public var interceptSuspiciousEnter: Bool = true
    /// Automatic AI translation on Enter.
    public var translation: TranslationSettings = TranslationSettings()

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
        usePersianDigits = try container.decodeIfPresent(Bool.self, forKey: .usePersianDigits) ?? false
        usePersianPunctuation = try container.decodeIfPresent(Bool.self, forKey: .usePersianPunctuation) ?? true
        englishModifier = try container.decodeIfPresent(EnglishModifier.self, forKey: .englishModifier) ?? .rightCommand
        convertSelection = try container.decodeIfPresent(Bool.self, forKey: .convertSelection) ?? true
        showPreview = try container.decodeIfPresent(Bool.self, forKey: .showPreview) ?? false
        lockLanguageFromSentenceStart = try container.decodeIfPresent(Bool.self, forKey: .lockLanguageFromSentenceStart) ?? true
        interceptSuspiciousEnter = try container.decodeIfPresent(Bool.self, forKey: .interceptSuspiciousEnter) ?? true
        translation = try container.decodeIfPresent(TranslationSettings.self, forKey: .translation) ?? TranslationSettings()
    }

    public init(
        isEnabled: Bool = true,
        mode: TypingMode = .automatic,
        priority: LanguagePriority = .automatic,
        usePersianDigits: Bool = false,
        usePersianPunctuation: Bool = true,
        englishModifier: EnglishModifier = .rightCommand,
        convertSelection: Bool = true,
        showPreview: Bool = false,
        lockLanguageFromSentenceStart: Bool = true,
        interceptSuspiciousEnter: Bool = true,
        translation: TranslationSettings = TranslationSettings()
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
        self.interceptSuspiciousEnter = interceptSuspiciousEnter
        self.translation = translation
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

/// Settings for AI translation on Enter.
public struct TranslationSettings: Codable, Equatable, Sendable {
    public static let defaultPrompt = "You are a professional translator. Translate the given Persian text into fluent, natural English. Output ONLY the translated text without explanations, quotes, or notes."

    public var isEnabled: Bool = false
    public var requireTriggerPrefix: Bool = true
    public var triggerPrefix: String = "ترجمه"
    public var provider: TranslationProvider = .minimax
    public var endpoint: String = TranslationProvider.minimax.defaultEndpoint
    public var apiKey: String = ""
    public var model: String = TranslationProvider.minimax.defaultModel
    public var systemPrompt: String = TranslationSettings.defaultPrompt

    public init() {}

    public init(
        isEnabled: Bool = false,
        requireTriggerPrefix: Bool = true,
        triggerPrefix: String = "ترجمه",
        provider: TranslationProvider = .minimax,
        endpoint: String = TranslationProvider.minimax.defaultEndpoint,
        apiKey: String = "",
        model: String = TranslationProvider.minimax.defaultModel,
        systemPrompt: String = TranslationSettings.defaultPrompt
    ) {
        self.isEnabled = isEnabled
        self.requireTriggerPrefix = requireTriggerPrefix
        self.triggerPrefix = triggerPrefix
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
    }

    /// Checks whether `line` matches the configured trigger prefix (if enabled)
    /// and returns the cleaned text to translate, or `nil` if the line should not be translated.
    public func extractTranslatableBody(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard requireTriggerPrefix else {
            return PersianText.containsPersian(trimmed) ? trimmed : nil
        }

        let configured = triggerPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty else {
            return PersianText.containsPersian(trimmed) ? trimmed : nil
        }

        // Support comma/semicolon-separated multiple prefixes, plus their Latin/Persian keyboard equivalents
        let rawPrefixes = configured
            .components(separatedBy: CharacterSet(charactersIn: ",،;|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var prefixes: [String] = []
        for p in rawPrefixes {
            if !prefixes.contains(p) { prefixes.append(p) }
            if let converted = PersianLayout.convert(p), !prefixes.contains(converted) {
                prefixes.append(converted)
            }
            if let latin = PersianLayout.convertToLatin(p), !prefixes.contains(latin) {
                prefixes.append(latin)
            }
        }
        if configured == "ترجمه" {
            for alias in ["jv[li", "/tr", "tr:"] where !prefixes.contains(alias) {
                prefixes.append(alias)
            }
        }

        for prefix in prefixes {
            let lowerTrimmed = trimmed.lowercased()
            let lowerPrefix = prefix.lowercased()
            if lowerTrimmed.hasPrefix(lowerPrefix) {
                let afterPrefixIndex = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
                let remainder = trimmed[afterPrefixIndex...]
                // Ensure the prefix is followed by whitespace or punctuation (like ':' or '-') so it matches a whole word/prefix
                if let firstRem = remainder.first {
                    let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：-—،,"))
                    guard firstRem.unicodeScalars.allSatisfy({ separators.contains($0) }) else {
                        continue
                    }
                }
                let cleaned = remainder
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：-—،,")))
                guard !cleaned.isEmpty, PersianText.containsPersian(cleaned) else {
                    return nil
                }
                return cleaned
            }
        }

        return nil
    }
}

/// The user's own dictionary: Persian words that must always convert, and
/// English words that must never convert.
public struct PersonalDictionary: Codable, Equatable, Sendable {
    public var persianWords: [String] = []
    public var englishWords: [String] = []

    public init() {}

    /// Reads the dictionary, ignoring keys that are missing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        persianWords = try container.decodeIfPresent([String].self, forKey: .persianWords) ?? []
        englishWords = try container.decodeIfPresent([String].self, forKey: .englishWords) ?? []
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
