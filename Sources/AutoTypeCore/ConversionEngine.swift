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

/// The language a sentence is being written in.
///
/// The engine follows the language of the sentence while the user types: the
/// first word with a single clear reading decides it, and the rest of the
/// sentence is read the same way.
public enum SentenceLanguage: String, Codable, CaseIterable, Sendable {
    /// Nothing has decided the language yet.
    case unknown
    /// The sentence is being written in Persian.
    case persian
    /// The sentence is being written in English.
    case english
}

/// Context the engine uses to disambiguate homographs such as *fun* / *leg*.
public struct ConversionContext: Sendable, Equatable {
    /// `true` when the previously committed word was Persian.
    public var previousWasPersian: Bool
    /// The previously committed Persian word, when there was one.
    public var previousPersianWord: String?
    /// The language of the sentence the word belongs to.
    ///
    /// It stays `.unknown` until a word with a single clear reading has been
    /// seen — that word is the one that decides the language of the sentence.
    /// A word that both dictionaries know does not decide anything.
    public var sentenceLanguage: SentenceLanguage

    public init(
        previousWasPersian: Bool = false,
        previousPersianWord: String? = nil,
        sentenceLanguage: SentenceLanguage = .unknown
    ) {
        self.previousWasPersian = previousWasPersian
        self.previousPersianWord = previousPersianWord
        self.sentenceLanguage = sentenceLanguage
    }

    /// `true` when the text around the caret is Persian.
    public var isPersian: Bool {
        sentenceLanguage == .persian || previousWasPersian
    }
}

/// The result of examining one typed word.
public struct WordOutcome: Sendable, Equatable {
    /// What the word should become.
    public let decision: WordDecision
    /// The context the next word should be judged in.
    public let context: ConversionContext

    public init(decision: WordDecision, context: ConversionContext) {
        self.decision = decision
        self.context = context
    }

    /// The text the word should be replaced with.
    public var output: String { decision.output }
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
        resolve(token: token, context: context).decision
    }

    /// Decides what a typed word should become, and how the sentence around it
    /// should be read from now on.
    ///
    /// The returned context carries the language of the sentence forward: a
    /// word that can only be Persian makes the sentence Persian, a word that
    /// can only be English makes it English, and a word that both dictionaries
    /// know leaves the sentence undecided.
    public func resolve(token: String, context: ConversionContext = ConversionContext()) -> WordOutcome {
        var context = context

        guard !token.isEmpty else {
            return WordOutcome(decision: .keepAsTyped(token), context: context)
        }

        // Technical strings are protected before any language scoring. They
        // also say something about the sentence: an address, an e-mail or a
        // file path is not Persian. They only decide the sentence when the
        // sentence has not been decided yet — a URL in the middle of a
        // Persian sentence does not turn it into an English one.
        if TechnicalPatterns.isTechnical(token) && !token.contains("\u{200C}") {
            let isPureNumber = token.allSatisfy(\.isNumber)
            if settings.lockLanguageFromSentenceStart, context.sentenceLanguage == .unknown, !isPureNumber {
                context.sentenceLanguage = .english
            }
            if !isPureNumber {
                context.previousWasPersian = false
                context.previousPersianWord = nil
            }
            let outputText: String
            if isPureNumber && settings.usePersianDigits && context.isPersian {
                outputText = PersianText.persianDigits(token)
            } else {
                outputText = token
            }
            return WordOutcome(decision: .keepAsTyped(outputText), context: context)
        }

        // Hyphenated compound words, slugs, and kebab-case identifiers.
        if let hyphenated = evaluateHyphenated(token: token, context: context) {
            if settings.lockLanguageFromSentenceStart {
                switch hyphenated.evidence {
                case .persian: context.sentenceLanguage = .persian
                case .english: context.sentenceLanguage = .english
                case .none: break
                }
            }
            switch hyphenated.decision {
            case .convertToPersian(let persian):
                context.previousWasPersian = true
                context.previousPersianWord = persian
            case .keepAsTyped:
                context.previousWasPersian = false
                context.previousPersianWord = nil
            }
            return WordOutcome(decision: hyphenated.decision, context: context)
        }

        var best: Evaluation?

        for candidate in Self.segmentations(of: token) {
            let evaluation = evaluate(core: candidate.core, context: context)
            if best == nil || evaluation.score > best!.score {
                best = evaluation
                best?.suffix = candidate.suffix
            }
        }

        // If the token explicitly has a ZWNJ and could convert to Persian, force Persian
        if token.contains("\u{200C}"), let persian = PersianLayout.convert(token) {
            if settings.lockLanguageFromSentenceStart {
                context.sentenceLanguage = .persian
            }
            context.previousWasPersian = true
            context.previousPersianWord = persian
            return WordOutcome(decision: .convertToPersian(persian), context: context)
        }

        guard let best else {
            return WordOutcome(decision: .keepAsTyped(token), context: context)
        }

        var decision: WordDecision
        switch best.decision {
        case .convertToPersian(let text): decision = .convertToPersian(text + best.suffix)
        case .keepAsTyped(let text): decision = .keepAsTyped(text + best.suffix)
        }

        // A word with a single clear reading decides the language of the
        // sentence. A word that both dictionaries know does not: it is only
        // read the way the sentence reads.
        if settings.lockLanguageFromSentenceStart {
            switch best.evidence {
            case .persian: context.sentenceLanguage = .persian
            case .english: context.sentenceLanguage = .english
            case .none: break
            }
        }

        switch decision {
        case .convertToPersian(let persian):
            context.previousWasPersian = true
            context.previousPersianWord = persian
        case .keepAsTyped:
            context.previousWasPersian = false
            context.previousPersianWord = nil
        }

        return WordOutcome(decision: decision, context: context)
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
            let outcome = resolve(token: word, context: context)
            var output = outcome.output
            if settings.usePersianDigits && (context.isPersian || outcome.context.isPersian) {
                output = PersianText.persianDigits(output)
            }
            result += output
            context = outcome.context
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

    /// What a word tells us about the language of the sentence around it.
    private enum Evidence {
        /// The word does not say anything about the sentence.
        case none
        /// The word can only be Persian: it decides the sentence.
        case persian
        /// The word can only be English: it decides the sentence.
        case english
    }

    /// The score of one candidate reading of a word.
    private struct Evaluation {
        var score: Int
        var decision: WordDecision
        var evidence: Evidence
        /// The punctuation that trailed the word.
        var suffix: String = ""

        init(score: Int, decision: WordDecision, evidence: Evidence) {
            self.score = score
            self.decision = decision
            self.evidence = evidence
        }
    }

    private func evaluate(core: String, context: ConversionContext) -> Evaluation {
        guard !core.isEmpty else {
            return Evaluation(score: 0, decision: .keepAsTyped(core), evidence: .none)
        }

        // A contraction is English, whatever the dictionary says.
        if TechnicalPatterns.isContraction(core) {
            return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(core), evidence: .english)
        }

        // Not every Latin token can be Persian: digits and symbols rule it out.
        guard let persian = PersianLayout.convert(core) else {
            return Evaluation(score: 0, decision: .keepAsTyped(core), evidence: .none)
        }

        // If the user explicitly typed a Persian ZWNJ (Shift+Space) inside the word,
        // they unequivocally intend Persian.
        if core.contains("\u{200C}") {
            let outputPersian = settings.fixTransposedCharacters ? (transposedPersianWord(for: persian) ?? persian) : persian
            return Evaluation(score: Weight.persianCommon, decision: .convertToPersian(outputPersian), evidence: .persian)
        }

        let rawPersianEntry = lexicon.persianEntry(for: persian)
        let exactClitic = rawPersianEntry == nil ? cliticConversion(of: persian) : nil
        let exactEnglishHit = lexicon.containsEnglish(core)
        let exactEnglishCommon = exactEnglishHit && lexicon.isCommonEnglish(core)

        // Transposition auto-correction for fast-typing character swaps (when enabled).
        let transposedPersian: PersianEntry?
        let transposedEnglish: String?
        if settings.fixTransposedCharacters {
            if !exactEnglishHit {
                let key = PersianText.lookupKey(persian)
                if let override = Self.persianTranspositionOverrides[key] {
                    transposedPersian = PersianEntry(canonical: override, isCommon: true)
                } else if (rawPersianEntry == nil || !rawPersianEntry!.isCommon) && exactClitic == nil {
                    transposedPersian = findTransposedPersianEntry(for: persian)
                } else {
                    transposedPersian = nil
                }
            } else {
                transposedPersian = nil
            }

            if !exactEnglishHit,
               core.count >= 3,
               core.allSatisfy({ $0.isASCII && $0.isLetter }) {
                let lower = core.lowercased()
                if let override = Self.englishTranspositionOverrides[lower] {
                    transposedEnglish = Self.matchCase(of: core, to: override)
                } else if rawPersianEntry?.isCommon != true && exactClitic == nil {
                    transposedEnglish = findTransposedEnglishWord(for: core)
                } else {
                    transposedEnglish = nil
                }
            } else {
                transposedEnglish = nil
            }
        } else {
            transposedPersian = nil
            transposedEnglish = nil
        }

        // If an explicit English transposition override matched (such as "adn" -> "and")
        // while the sentence is not Persian, prefer the English correction over a rare/homograph Persian reading.
        let preferTransposedEnglishOverride: Bool = {
            guard transposedEnglish != nil else { return false }
            let lower = core.lowercased()
            guard Self.englishTranspositionOverrides[lower] != nil else { return false }
            return !context.isPersian && settings.priority != .persianFirst
        }()

        let persianEntry: PersianEntry?
        if preferTransposedEnglishOverride {
            persianEntry = nil
        } else if let transposedPersian {
            persianEntry = transposedPersian
        } else {
            persianEntry = rawPersianEntry
        }

        let effectiveEnglishWord = transposedEnglish ?? core
        let englishHit = exactEnglishHit || (transposedEnglish != nil)
        let englishCommon = exactEnglishCommon || (transposedEnglish != nil)

        // A word that only has a Persian reading: either the English
        // dictionary does not know the spelling at all, or the spelling it
        // knows is meaningless («از» is spelled `hc`).
        let persianOnly: Bool
        if let persianEntry {
            persianOnly = !englishHit || PersianOnlyWords.contains(persianEntry.canonical)
        } else {
            persianOnly = false
        }

        // The user pressed a key that only exists on a Persian keyboard inside
        // a word (or at the end of a valid Persian word) — that is proof of what
        // the word is, whatever the sentence around it says.
        let provesPersian = PersianLayout.containsInteriorPersianOnlyKey(core) ||
            (core.count > 1 && PersianLayout.persianOnlyKeys.contains(core.last!) && persianEntry != nil)

        let locked = settings.lockLanguageFromSentenceStart ? context.sentenceLanguage : .unknown

        switch locked {
        case .persian:
            // The sentence is Persian, so it stays Persian. The only words
            // that stay English are the ones with a meaningful English
            // reading and no meaningful Persian one.
            if let persianEntry {
                return Evaluation(score: persianEntry.isCommon ? Weight.persianCommon : Weight.persianRare,
                                  decision: .convertToPersian(persianEntry.canonical),
                                  evidence: .none)
            }
            if let clitic = exactClitic ?? cliticConversion(of: persian) {
                return Evaluation(score: Weight.persianRare, decision: .convertToPersian(clitic), evidence: .none)
            }
            if !englishHit {
                return Evaluation(score: Weight.heuristic, decision: .convertToPersian(persian), evidence: .none)
            }
            return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(effectiveEnglishWord), evidence: .none)

        case .english:
            // Standalone Latin letters inside an English sentence stay as typed (e.g. "x", "y", "a", "b")
            if core.count == 1 && core.allSatisfy({ $0.isLetter }) {
                return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(core), evidence: .none)
            }
            // The sentence is English, so it stays English — unless the word
            // itself proves that the author switched to Persian.
            //
            // A word that has no meaningful English reading is that proof:
            // there is nothing English about it to keep. It stays Persian and
            // the sentence follows it.
            if persianOnly, let persianEntry {
                return Evaluation(score: persianEntry.isCommon ? Weight.persianCommon : Weight.persianRare,
                                  decision: .convertToPersian(persianEntry.canonical),
                                  evidence: .persian)
            }
            if provesPersian {
                if let persianEntry {
                    return Evaluation(score: persianEntry.isCommon ? Weight.persianCommon : Weight.persianRare,
                                      decision: .convertToPersian(persianEntry.canonical),
                                      evidence: .persian)
                }
                if let clitic = exactClitic ?? cliticConversion(of: persian) {
                    return Evaluation(score: Weight.persianRare, decision: .convertToPersian(clitic), evidence: .persian)
                }
                return Evaluation(score: Weight.persianCommon, decision: .convertToPersian(persian), evidence: .persian)
            }
            if englishHit {
                return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(effectiveEnglishWord), evidence: .none)
            }
            // Not an English dictionary word: since the sentence is English,
            // unknown words (names, typos, slang, technical terms) stay as typed
            // unless they proved Persian above.
            return Evaluation(score: Weight.englishRare, decision: .keepAsTyped(core), evidence: .none)

        case .unknown:
            break
        }

        // The sentence has not been decided yet: the word decides it.
        if let persianEntry {
            if englishHit && !persianOnly {
                return resolveAmbiguous(
                    core: effectiveEnglishWord,
                    persianEntry: persianEntry,
                    englishCommon: englishCommon,
                    context: context
                )
            }
            // Only one reading: this word is Persian, and it says so.
            return Evaluation(score: persianEntry.isCommon ? Weight.persianCommon : Weight.persianRare,
                              decision: .convertToPersian(persianEntry.canonical),
                              evidence: .persian)
        }

        // Not a dictionary word. Try the Persian clitic rules: "کتاب‌ها" and
        // "می‌رفت" are built by attaching a suffix or prefix to a known word.
        if let clitic = exactClitic ?? cliticConversion(of: persian) {
            return Evaluation(score: Weight.persianRare, decision: .convertToPersian(clitic), evidence: .none)
        }

        if englishHit {
            // Only one reading: this word is English, and it says so.
            return Evaluation(score: englishCommon ? Weight.englishCommon : Weight.englishRare,
                              decision: .keepAsTyped(effectiveEnglishWord),
                              evidence: .english)
        }

        // An apostrophe inside a word whose stem is English means a contraction.
        if let stem = apostropheStem(core), lexicon.containsEnglish(stem) {
            return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(core), evidence: .english)
        }

        // Unknown to both dictionaries. Since it is not an English dictionary
        // word and converts cleanly to Persian characters, it should convert to Persian.
        return Evaluation(score: Weight.heuristic, decision: .convertToPersian(persian), evidence: .none)
    }

    /// Resolves a word that both dictionaries recognise.
    ///
    /// Such a word is read the way the sentence reads. When the sentence has
    /// not been decided yet the rule the user picked decides.
    private func resolveAmbiguous(
        core: String,
        persianEntry: PersianEntry,
        englishCommon: Bool,
        context: ConversionContext
    ) -> Evaluation {
        switch settings.priority {
        case .englishFirst:
            return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(core), evidence: .none)
        case .persianFirst:
            return Evaluation(score: Weight.persianCommon, decision: .convertToPersian(persianEntry.canonical), evidence: .none)
        case .automatic:
            // If the sentence or preceding word is Persian, ambiguous words (like "fun" / "بعد") convert to Persian.
            if context.isPersian {
                return Evaluation(score: Weight.persianCommon, decision: .convertToPersian(persianEntry.canonical), evidence: .none)
            }
            if persianEntry.isCommon && !englishCommon {
                return Evaluation(score: Weight.persianCommon, decision: .convertToPersian(persianEntry.canonical), evidence: .none)
            }
            if englishCommon && !persianEntry.isCommon {
                return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(core), evidence: .none)
            }
            return Evaluation(score: Weight.englishRare, decision: .keepAsTyped(core), evidence: .none)
        }
    }

    // MARK: - Character Transposition Auto-Correction

    /// High-priority Persian transposition overrides for very common fast-typing character swaps.
    public static let persianTranspositionOverrides: [String: String] = [
        "لاسم": "سلام",
        "لسام": "سلام",
        "تکاب": "کتاب",
        "کتبا": "کتاب",
        "انلگیس": "انگلیس",
        "انلگیسی": "انگلیسی",
        "انگیلس": "انگلیس",
        "انگیلسی": "انگلیسی",
        "انگلسی": "انگلیسی",
        "انگلسیی": "انگلیسی",
        "انگلییس": "انگلیسی",
        "فراسی": "فارسی",
        "فاسری": "فارسی",
        "فاریس": "فارسی",
        "برنماه": "برنامه",
        "برمانه": "برنامه",
        "برانمه": "برنامه",
        "سیتسم": "سیستم",
        "سسیتم": "سیستم",
        "سیسمت": "سیستم",
        "موفیقت": "موفقیت",
        "موقفتی": "موفقیت",
        "موقفیت": "موفقیت",
        "پرژوه": "پروژه",
        "پورژه": "پروژه",
        "تیاپ": "تایپ",
        "تاپی": "تایپ",
        "چطروی": "چطوری",
        "چوطری": "چطوری",
        "مکشل": "مشکل",
        "مشلک": "مشکل",
        "کمله": "کلمه",
        "جلمه": "جمله",
        "دسرت": "درست",
        "اشبتاه": "اشتباه",
        "اشتابه": "اشتباه",
        "کاراتکر": "کاراکتر",
        "کارکاتر": "کاراکتر",
    ]

    /// High-priority English transposition overrides for frequent fast-typing character swaps.
    public static let englishTranspositionOverrides: [String: String] = [
        "teh": "the", "hte": "the",
        "adn": "and", "nad": "and",
        "taht": "that", "htat": "that",
        "wiht": "with", "wtih": "with", "iwth": "with",
        "thier": "their", "tehir": "their", "hteir": "their",
        "tehre": "there", "htere": "there", "theer": "there",
        "recieve": "receive", "recevie": "receive",
        "freind": "friend", "firend": "friend",
        "wierd": "weird", "werid": "weird",
        "becuase": "because", "beacuse": "because", "becasue": "because",
        "ahve": "have", "hvae": "have",
        "tihs": "this", "thsi": "this", "htis": "this",
        "waht": "what", "hwat": "what", "whta": "what",
        "wrod": "word", "wodr": "word",
        "wrold": "world", "wolrd": "world",
        "ehllo": "hello", "hlelo": "hello", "helol": "hello",
        "enlgish": "english", "engilsh": "english", "egnlish": "english", "englsih": "english",
        "presian": "persian", "pesrian": "persian", "perisan": "persian",
        "sytsem": "system", "sysetm": "system", "systme": "system",
        "tpye": "type", "tyep": "type", "ytpe": "type",
        "abotu": "about", "abuot": "about", "aobut": "about",
        "woudl": "would", "wolud": "would", "wuold": "would",
        "shoudl": "should", "sholud": "should", "shuold": "should",
        "coudl": "could", "colud": "could", "cuold": "could",
        "wirte": "write", "wrtie": "write", "rwite": "write",
        "ohter": "other", "otehr": "other", "toher": "other", "othre": "other",
        "whcih": "which", "wihch": "which", "whihc": "which",
    ]

    /// Returns the corrected Persian word if `persian` has transposed characters, or `nil` if no transposition correction applies.
    public func transposedPersianWord(for persian: String) -> String? {
        guard settings.fixTransposedCharacters else { return nil }
        let key = PersianText.lookupKey(persian)
        guard key.count >= 3 else { return nil }
        if let override = Self.persianTranspositionOverrides[key] {
            return override
        }
        if let exact = lexicon.persianEntry(for: persian), exact.isCommon {
            return nil
        }
        if cliticConversion(of: persian) != nil {
            return nil
        }
        return findTransposedPersianEntry(for: persian)?.canonical
    }

    private func findTransposedPersianEntry(for persian: String) -> PersianEntry? {
        let key = PersianText.lookupKey(persian)
        guard key.count >= 3 else { return nil }
        if let override = Self.persianTranspositionOverrides[key] {
            return PersianEntry(canonical: override, isCommon: true)
        }

        let candidates = Self.transpositionCandidates(of: key)

        // 1. Check direct common Persian dictionary hits
        for candidate in candidates {
            if let entry = lexicon.persianEntry(for: candidate), entry.isCommon {
                return entry
            }
        }

        // 2. Check clitics (plural/prefix forms like "برنماه‌ها" -> "برنامه‌ها")
        for candidate in candidates {
            if let (stem, suffix) = PersianText.splitCliticSuffix(candidate),
               let entry = lexicon.persianEntry(for: stem), entry.isCommon {
                let canonical = entry.canonical + String(PersianText.zeroWidthNonJoiner) + suffix
                return PersianEntry(canonical: canonical, isCommon: true)
            }
            if let (prefix, stem) = PersianText.splitCliticPrefix(candidate),
               let entry = lexicon.persianEntry(for: stem), entry.isCommon {
                let canonical = prefix + String(PersianText.zeroWidthNonJoiner) + entry.canonical
                return PersianEntry(canonical: canonical, isCommon: true)
            }
        }

        return nil
    }

    private func findTransposedEnglishWord(for word: String) -> String? {
        let lower = word.lowercased()
        guard lower.count >= 3 else { return nil }
        if let override = Self.englishTranspositionOverrides[lower] {
            return Self.matchCase(of: word, to: override)
        }

        let candidates = Self.transpositionCandidates(of: lower)
        for candidate in candidates {
            if lexicon.isCommonEnglish(candidate) {
                return Self.matchCase(of: word, to: candidate)
            }
        }

        // For 6+ character English words, also check the full English lexicon on single adjacent swaps
        if lower.count >= 6 {
            let chars = Array(lower)
            for i in 0..<(chars.count - 1) where chars[i] != chars[i + 1] {
                var swapped = chars
                swapped.swapAt(i, i + 1)
                let candidate = String(swapped)
                if lexicon.containsEnglish(candidate) {
                    return Self.matchCase(of: word, to: candidate)
                }
            }
        }

        return nil
    }

    /// Generates transposition candidates ordered by likelihood:
    /// 1) Single adjacent character swaps `(i, i + 1)`
    /// 2) Gapped distance-2 character swaps `(i, i + 2)` for words of length >= 4
    /// 3) Two disjoint adjacent swaps `(i, i + 1)` and `(j, j + 1)` for words of length >= 5
    static func transpositionCandidates(of text: String) -> [String] {
        let chars = Array(text)
        let n = chars.count
        guard n >= 3 else { return [] }

        var results: [String] = []
        results.reserveCapacity(n * 2)

        // 1. Single adjacent swaps
        for i in 0..<(n - 1) where chars[i] != chars[i + 1] {
            var c = chars
            c.swapAt(i, i + 1)
            results.append(String(c))
        }

        // 2. Distance-2 swaps (when a middle key was struck between two swapped keys)
        if n >= 4 {
            for i in 0..<(n - 2) where chars[i] != chars[i + 2] {
                var c = chars
                c.swapAt(i, i + 2)
                results.append(String(c))
            }
        }

        // 3. Two disjoint adjacent swaps in longer words
        if n >= 5 {
            for i in 0..<(n - 3) where chars[i] != chars[i + 1] {
                for j in (i + 2)..<(n - 1) where chars[j] != chars[j + 1] {
                    var c = chars
                    c.swapAt(i, i + 1)
                    c.swapAt(j, j + 1)
                    results.append(String(c))
                }
            }
        }

        return results
    }

    /// Preserves the capitalization pattern (ALL CAPS or Title Case) of `original` when applying `lowercaseMatch`.
    private static func matchCase(of original: String, to lowercaseMatch: String) -> String {
        guard !original.isEmpty, !lowercaseMatch.isEmpty else { return lowercaseMatch }
        if original == original.uppercased() && original != original.lowercased() {
            return lowercaseMatch.uppercased()
        }
        if let first = original.first, first.isUppercase,
           original.dropFirst() == original.dropFirst().lowercased() {
            return lowercaseMatch.prefix(1).uppercased() + lowercaseMatch.dropFirst()
        }
        return lowercaseMatch
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

    /// Evaluates tokens with hyphens (e.g. `shakiba-academy-beauty`, `sghl-]xhvd`, `sghl-sghl`).
    private func evaluateHyphenated(token: String, context: ConversionContext) -> Evaluation? {
        guard token.contains("-"), !token.contains("\u{200C}") else { return nil }
        let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }

        var hasPersianPart = false
        var convertedParts: [String] = []
        for part in parts {
            if let persian = PersianLayout.convert(part) {
                let exactEntry = lexicon.persianEntry(for: persian)
                let transposedEntry = (settings.fixTransposedCharacters && (exactEntry == nil || !exactEntry!.isCommon))
                    ? findTransposedPersianEntry(for: persian)
                    : nil
                let resolvedEntry = transposedEntry ?? exactEntry
                if resolvedEntry != nil || PersianLayout.containsInteriorPersianOnlyKey(part) || PersianLayout.persianOnlyKeys.contains(part.last ?? " ") {
                    hasPersianPart = true
                    convertedParts.append(resolvedEntry?.canonical ?? persian)
                    continue
                }
            }
            convertedParts.append(part)
        }

        if hasPersianPart {
            let result = convertedParts.joined(separator: "-")
            return Evaluation(score: Weight.persianCommon, decision: .convertToPersian(result), evidence: .persian)
        }

        // Neither part has Persian evidence -> English slug, identifier or compound
        return Evaluation(score: Weight.englishCommon, decision: .keepAsTyped(token), evidence: .english)
    }
}
