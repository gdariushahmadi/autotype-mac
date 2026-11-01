import Foundation

/// How AutoType decides what a typed word is.
public enum TypingMode: String, Codable, CaseIterable, Sendable {
    /// Type with the English layout; Persian words are detected and converted.
    case automatic
    /// Every key produces its Persian letter immediately (a plain Persian layout).
    case directPersian
}

/// Which language wins when a word could be either.
public enum LanguagePriority: String, Codable, CaseIterable, Sendable {
    /// Use commonness and the surrounding context.
    case automatic
    /// Prefer Persian whenever both readings are possible.
    case persianFirst
    /// Prefer English whenever both readings are possible.
    case englishFirst
}

/// The key that, while held, types plain English without conversion.
public enum EnglishModifier: String, Codable, CaseIterable, Sendable {
    case none
    case rightCommand
    case rightOption
    case rightShift
    case leftShift

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .rightCommand: return "Right Command"
        case .rightOption: return "Right Option"
        case .rightShift: return "Right Shift"
        case .leftShift: return "Left Shift"
        }
    }
}

/// The result of examining one typed word.
public enum WordDecision: Equatable, Sendable {
    /// The word was Persian and should be replaced by this text.
    case convertToPersian(String)
    /// The word stays exactly as it was typed.
    case keepAsTyped(String)

    public var output: String {
        switch self {
        case .convertToPersian(let text): return text
        case .keepAsTyped(let text): return text
        }
    }
}

/// Context the engine uses to disambiguate homographs such as *fun* / *leg*.
public struct ConversionContext: Sendable, Equatable {
    /// `true` when the previously committed word was Persian.
    public var previousWasPersian: Bool
    /// The previously committed Persian word, when there was one.
    public var previousPersianWord: String?
    /// If lockLanguageFromSentenceStart is active:
    /// `true` if current sentence started with Persian, `false` if English, `nil` if sentence just started.
    public var sentenceLanguageIsPersian: Bool?

    public init(
        previousWasPersian: Bool = false,
        previousPersianWord: String? = nil,
        sentenceLanguageIsPersian: Bool? = nil
    ) {
        self.previousWasPersian = previousWasPersian
        self.previousPersianWord = previousPersianWord
        self.sentenceLanguageIsPersian = sentenceLanguageIsPersian
    }
}

/// Turns Latin keystrokes into Persian when the evidence says so.
public final class ConversionEngine {

    // Confidence weights. They are only compared against each other when
    // choosing between competing readings of the same token, so the exact
    // numbers matter less than their ordering.
    private enum Weight {
        static let persianCommon = 100
        static let persianRare = 80
        static let englishCommon = 90
        static let englishRare = 70
        static let heuristic = 40
        static let unknown = 10
    }

    public let lexicon: Lexicon
    public var settings: ConversionSettings {
        didSet { onSettingsChange?(oldValue, settings) }
    }

    /// Hook used by the UI to react to a settings change.
    public var onSettingsChange: ((ConversionSettings, ConversionSettings) -> Void)?

    public init(lexicon: Lexicon, settings: ConversionSettings = ConversionSettings()) {
        self.lexicon = lexicon
        self.settings = settings
    }

    // MARK: - Public API

    /// Decides what a typed word should become.
    public func decide(token: String, context: ConversionContext = ConversionContext()) -> WordDecision {
        guard !token.isEmpty else { return .keepAsTyped(token) }

        // Technical strings are protected before any language scoring.
        if TechnicalPatterns.isTechnical(token) && !token.contains("\u{200C}") {
            return .keepAsTyped(token)
        }

        var best: (score: Int, decision: WordDecision, suffix: String)?

        for candidate in Self.segmentations(of: token) {
            let evaluation = evaluate(core: candidate.core, context: context)
            if best == nil || evaluation.score > best!.score {
                best = (evaluation.score, evaluation.decision, candidate.suffix)
            }
        }

        // If the token explicitly has a ZWNJ and could convert to Persian, force Persian
        if token.contains("\u{200C}"), let persian = PersianLayout.convert(token) {
            return .convertToPersian(persian)
        }

        guard let best else { return .keepAsTyped(token) }
        switch best.decision {
        case .convertToPersian(let text): return .convertToPersian(text + best.suffix)
        case .keepAsTyped(let text): return .keepAsTyped(text + best.suffix)
        }
    }

    /// The Persian letter a key produces in direct mode, if any.
    public func directPersianLetter(for key: Character) -> Character? {
        PersianLayout.convert(key)
    }

    /// Converts a piece of text that was already selected in the editor.
    ///
    /// Unlike the word-at-a-time path this always converts, because the user
    /// asked for it explicitly.
    public func convertSelection(_ text: String) -> String {
        guard let persian = PersianLayout.convert(text) else { return text }
        return persian
    }

    /// Converts a whole passage, one word at a time.
    ///
    /// `convertSelection(_:)` maps every letter, so an English word comes
    /// back as gibberish Persian letters. This walks the passage the same way
    /// the typing path does: every word is looked up in the dictionary and
    /// only the words that really are Persian are replaced. Whitespace,
    /// punctuation, numbers and technical strings are kept exactly as they
    /// were.
    public func convertText(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var word = ""
        var context = ConversionContext()

        func commit() {
            guard !word.isEmpty else { return }
            let decision = decide(token: word, context: context)
            switch decision {
            case .convertToPersian(let persian):
                result += persian
                let locked = context.sentenceLanguageIsPersian ?? true
                context = ConversionContext(
                    previousWasPersian: true,
                    previousPersianWord: persian,
                    sentenceLanguageIsPersian: locked
                )
            case .keepAsTyped(let kept):
                result += kept
                let locked = context.sentenceLanguageIsPersian ?? false
                context = ConversionContext(
                    previousWasPersian: false,
                    previousPersianWord: nil,
                    sentenceLanguageIsPersian: locked
                )
            }
            // A full stop ends the sentence, so the next word is judged on
            // its own again.
            if word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?")
                || word.hasSuffix("؟") {
                context = ConversionContext()
            }
            word = ""
        }

        for character in text {
            if character.isWhitespace {
                commit()
                result.append(character)
                if character == "\n" {
                    context = ConversionContext()
                }
            } else {
                word.append(character)
            }
        }
        commit()

        return result
    }

    /// Converts the word immediately before the caret.
    public func convertWord(before text: String) -> String? {
        guard let index = text.lastIndex(where: { $0 == " " || $0 == "\n" }) else {
            return decide(token: text).output
        }
        let word = String(text[text.index(after: index)...])
        guard !word.isEmpty else { return nil }
        let decision = decide(token: word)
        guard case .convertToPersian(let converted) = decision else { return nil }
        return converted
    }

    // MARK: - Candidate segmentation

    /// Splits a token into the part that may be a word plus the punctuation
    /// that trails it.
    ///
    /// `"hello,"` yields `("hello", ",")` and `"o,f"` yields `("o,f", "")` —
    /// the comma is the Persian letter `و` when it belongs to the word, and
    /// punctuation when it does not.
    static func segmentations(of token: String) -> [(core: String, suffix: String)] {
        var result: [(core: String, suffix: String)] = [(token, "")]
        var suffix = ""
        var core = token
        while let last = core.last, !last.isLetter, !last.isNumber, last != "\u{200C}" {
            suffix = String(last) + suffix
            core.removeLast()
            if core.isEmpty { break }
            result.append((core, suffix))
        }
        return result
    }

    // MARK: - Scoring

    private func evaluate(core: String, context: ConversionContext) -> (score: Int, decision: WordDecision) {
        guard !core.isEmpty else { return (0, .keepAsTyped(core)) }

        // A contraction is English, whatever the dictionary says.
        if TechnicalPatterns.isContraction(core) {
            return (Weight.englishCommon, .keepAsTyped(core))
        }

        // Not every Latin token can be Persian: digits and symbols rule it out.
        guard let persian = PersianLayout.convert(core) else {
            return (0, .keepAsTyped(core))
        }

        // If the user explicitly typed a Persian ZWNJ (Shift+Space) inside the word,
        // they unequivocally intend Persian.
        if core.contains("\u{200C}") {
            return (Weight.persianCommon, .convertToPersian(persian))
        }

        let persianEntry = lexicon.persianEntry(for: persian)
        let englishHit = lexicon.containsEnglish(core)
        let englishCommon = englishHit && lexicon.isCommonEnglish(core)

        // If sentence language locking is enabled and has already locked onto a language for this sentence:
        if settings.lockLanguageFromSentenceStart, let lockedPersian = context.sentenceLanguageIsPersian {
            if lockedPersian {
                // The sentence started with Persian. Strongly favor Persian.
                if let persianEntry {
                    return (Weight.persianCommon, .convertToPersian(persianEntry.canonical))
                }
                if let clitic = cliticConversion(of: persian) {
                    return (Weight.persianRare, .convertToPersian(clitic))
                }
                if !englishHit {
                    return (Weight.heuristic, .convertToPersian(persian))
                }
            } else {
                // The sentence started with English. Strongly favor English.
                if englishHit {
                    return (Weight.englishCommon, .keepAsTyped(core))
                }
            }
        }

        if let persianEntry {
            if englishHit {
                return resolveAmbiguous(
                    core: core,
                    persian: persian,
                    persianEntry: persianEntry,
                    englishCommon: englishCommon,
                    context: context
                )
            }
            return (persianEntry.isCommon ? Weight.persianCommon : Weight.persianRare,
                    .convertToPersian(persianEntry.canonical))
        }

        // Not a dictionary word. Try the Persian clitic rules: "کتاب‌ها" and
        // "می‌رفت" are built by attaching a suffix or prefix to a known word.
        if let clitic = cliticConversion(of: persian) {
            return (Weight.persianRare, .convertToPersian(clitic))
        }

        if englishHit {
            return (englishCommon ? Weight.englishCommon : Weight.englishRare, .keepAsTyped(core))
        }

        // An apostrophe inside a word whose stem is English means a contraction.
        if let stem = apostropheStem(core), lexicon.containsEnglish(stem) {
            return (Weight.englishCommon, .keepAsTyped(core))
        }

        // Unknown to both dictionaries. Since it is not an English dictionary
        // word and converts cleanly to Persian characters, it should convert to Persian.
        return (Weight.heuristic, .convertToPersian(persian))
    }

    /// Two-letter Latin tokens that are technically in the system English dictionary
    /// as abbreviations, state codes, or musical notes, but in Persian typing
    /// are standard everyday Persian words (`می`, `من`, `تو`, `ما`, `رو`, `با`, `تا`, `جا`, `پا`, `دل`, `هم`, `چه`, `کی`, `نه`).
    private static let persianPreferredShortTokens: Set<String> = [
        "fi", // به
        "hc", // از (az)
        "ld", // می (mi - musical note)
        "lk", // من
        "j,", // تو
        "lh", // ما (ma)
        "v,", // رو
        "fh", // با
        "jh", // تا
        "[h", // جا
        "mh", // پا
        "ng", // دل
        "il", // هم
        "]i", // چه
        ";d", // کی
        "ki", // نه
        "n,", // دو
        "si", // سه (si - musical note)
        "hf", // اب
        "of", // خب
    ]

    /// Resolves a word that both dictionaries recognise.
    private func resolveAmbiguous(
        core: String,
        persian: String,
        persianEntry: PersianEntry,
        englishCommon: Bool,
        context: ConversionContext
    ) -> (score: Int, decision: WordDecision) {
        if Self.persianPreferredShortTokens.contains(core.lowercased()) {
            return (Weight.persianCommon, .convertToPersian(persianEntry.canonical))
        }
        if settings.lockLanguageFromSentenceStart, let lockedPersian = context.sentenceLanguageIsPersian {
            if lockedPersian {
                return (Weight.persianCommon, .convertToPersian(persianEntry.canonical))
            } else {
                return (Weight.englishCommon, .keepAsTyped(core))
            }
        }
        switch settings.priority {
        case .englishFirst:
            return (Weight.englishCommon, .keepAsTyped(core))
        case .persianFirst:
            return (Weight.persianCommon, .convertToPersian(persianEntry.canonical))
        case .automatic:
            // If the preceding word was Persian, ambiguous words (like "fun" / "بعد") convert to Persian.
            if context.previousWasPersian {
                return (Weight.persianCommon, .convertToPersian(persianEntry.canonical))
            }
            if context.sentenceLanguageIsPersian == false {
                return (Weight.englishCommon, .keepAsTyped(core))
            }
            if persianEntry.isCommon && !englishCommon {
                return (Weight.persianCommon, .convertToPersian(persianEntry.canonical))
            }
            if englishCommon && !persianEntry.isCommon {
                return (Weight.englishCommon, .keepAsTyped(core))
            }
            return (Weight.englishRare, .keepAsTyped(core))
        }
    }

    /// Applies the Persian clitic rules to a string that is not a dictionary
    /// word on its own.
    ///
    /// Every clitic that survives here is one that is *always* written with a
    /// ZWNJ, so the result is a correctly spelled word rather than a guess.
    private func cliticConversion(of persian: String) -> String? {
        if let (stem, suffix) = PersianText.splitCliticSuffix(persian),
           let entry = lexicon.persianEntry(for: stem) {
            return entry.canonical + String(PersianText.zeroWidthNonJoiner) + suffix
        }
        if let (prefix, stem) = PersianText.splitCliticPrefix(persian),
           let entry = lexicon.persianEntry(for: stem) {
            return prefix + String(PersianText.zeroWidthNonJoiner) + entry.canonical
        }
        return nil
    }

    /// The English stem of a token that contains an apostrophe, if any.
    private func apostropheStem(_ token: String) -> String? {
        guard let index = token.firstIndex(of: "'"), index != token.startIndex else { return nil }
        return String(token[token.startIndex..<index])
    }
}
