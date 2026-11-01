import Testing
import Foundation
@testable import AutoTypeCore

@Suite("Conversion engine")
struct ConversionEngineTests {

    private func makeEngine(settings: ConversionSettings = ConversionSettings()) throws -> ConversionEngine {
        ConversionEngine(lexicon: try AutoTypeResources.loadLexicon(), settings: settings)
    }

    private func convert(
        _ token: String,
        context: ConversionContext = ConversionContext(),
        engine: ConversionEngine
    ) -> String {
        engine.decide(token: token, context: context).output
    }

    private func isPersian(
        _ token: String,
        context: ConversionContext = ConversionContext(),
        engine: ConversionEngine
    ) -> Bool {
        if case .convertToPersian = engine.decide(token: token, context: context) { return true }
        return false
    }

    // MARK: - Persian words

    @Test("A common Persian word is converted")
    func commonPersianWord() throws {
        let engine = try makeEngine()
        #expect(convert("sghl", engine: engine) == "سلام")
        #expect(convert(";jhf", engine: engine) == "کتاب")
    }

    @Test("A Persian word typed with the comma key")
    func persianWordWithPunctuationKey() throws {
        let engine = try makeEngine()
        // «خوب» is typed with the comma key, which carries the letter و.
        #expect(convert("o,f", engine: engine) == "خوب")
    }

    @Test("A plural keeps its zero width non-joiner")
    func pluralZWNJ() throws {
        let engine = try makeEngine()
        #expect(convert(";jhfih", engine: engine) == "کتاب\u{200C}ها")
    }

    @Test("A verb prefix keeps its zero width non-joiner")
    func prefixZWNJ() throws {
        let engine = try makeEngine()
        #expect(convert("ldv,n", engine: engine) == "می\u{200C}رود")
    }

    @Test("A word that only looks like a clitic is left alone")
    func cliticLookalike() throws {
        let engine = try makeEngine()
        #expect(convert("khnj", engine: engine) == "نادت")
    }

    // MARK: - English words

    @Test("Common English words are kept")
    func commonEnglishWords() throws {
        let engine = try makeEngine()
        #expect(convert("hello", engine: engine) == "hello")
        #expect(convert("the", engine: engine) == "the")
        #expect(convert("world", engine: engine) == "world")
        #expect(convert("code", engine: engine) == "code")
    }

    @Test("An English word with a trailing comma keeps the comma")
    func englishWithTrailingComma() throws {
        let engine = try makeEngine()
        #expect(convert("hello,", engine: engine) == "hello,")
    }

    @Test("Contractions are protected")
    func contractions() throws {
        let engine = try makeEngine()
        #expect(convert("don't", engine: engine) == "don't")
        #expect(convert("it's", engine: engine) == "it's")
        #expect(convert("can't", engine: engine) == "can't")
    }

    // MARK: - Technical strings

    @Test("Technical strings are untouched", arguments: [
        "test@example.com",
        "https://example.com",
        "http://example.com/path",
        "192.168.1.1",
        "/usr/local/bin",
        "~/Documents/file.txt",
        "v1.2.3",
        "user_name",
        "camelCase",
        "#FF00AA",
        "12:30",
        "api",
        "json",
        "SwiftUI",
    ])
    func technicalStrings(token: String) throws {
        let engine = try makeEngine()
        #expect(convert(token, engine: engine) == token)
    }

    @Test("Numbers are untouched")
    func numbers() throws {
        let engine = try makeEngine()
        #expect(convert("123", engine: engine) == "123")
        #expect(convert("2024", engine: engine) == "2024")
    }

    @Test("Smart numbers: English at start, Persian inside Persian context, toggleable")
    func smartNumbersContextual() throws {
        var settings = ConversionSettings()
        settings.usePersianDigits = true
        let engine = try makeEngine(settings: settings)

        // 1. At start (no context): English digits
        let startOutcome = engine.resolve(token: "1403", context: ConversionContext())
        #expect(startOutcome.output == "1403")
        #expect(startOutcome.context.sentenceLanguage != .english) // Pure number does NOT lock to English

        // 2. Starting with a number does not prevent subsequent Persian word from converting
        let nextWordOutcome = engine.resolve(token: ";jhf", context: startOutcome.context)
        #expect(nextWordOutcome.output == "کتاب")

        // 3. Inside Persian context: numbers convert to Persian digits
        let persianContext = ConversionContext(previousWasPersian: true, previousPersianWord: "سلام", sentenceLanguage: .persian)
        let insidePersianOutcome = engine.resolve(token: "1403", context: persianContext)
        #expect(insidePersianOutcome.output == "۱۴۰۳")

        // 4. Inside English context: numbers stay English
        let englishContext = ConversionContext(previousWasPersian: false, sentenceLanguage: .english)
        let insideEnglishOutcome = engine.resolve(token: "1403", context: englishContext)
        #expect(insideEnglishOutcome.output == "1403")

        // 5. When disabled: numbers stay English even in Persian context
        var disabledSettings = ConversionSettings()
        disabledSettings.usePersianDigits = false
        let disabledEngine = try makeEngine(settings: disabledSettings)
        let disabledOutcome = disabledEngine.resolve(token: "1403", context: persianContext)
        #expect(disabledOutcome.output == "1403")
    }

    // MARK: - Ambiguity

    @Test("An ambiguous word defaults to English")
    func ambiguousDefaultsToEnglish() throws {
        let engine = try makeEngine()
        // «fun» is both an English word and the Persian «بعد».
        #expect(!isPersian("fun", engine: engine))
    }

    @Test("An ambiguous word follows the preceding Persian word")
    func ambiguousFollowsContext() throws {
        let engine = try makeEngine()
        let context = ConversionContext(previousWasPersian: true, previousPersianWord: "سلام")
        #expect(isPersian("fun", context: context, engine: engine))
    }

    @Test("The priority setting overrides the default")
    func prioritySetting() throws {
        var settings = ConversionSettings()
        settings.priority = .persianFirst
        let persianFirst = try makeEngine(settings: settings)
        #expect(isPersian("fun", engine: persianFirst))

        settings.priority = .englishFirst
        let englishFirst = try makeEngine(settings: settings)
        #expect(!isPersian("fun", engine: englishFirst))
    }

    // MARK: - Personal dictionary

    @Test("A personal Persian word always converts")
    func personalPersianWord() throws {
        let engine = try makeEngine()
        // «ل» lives on the g key, so "gggg" types «لللل».
        engine.lexicon.personalPersian = ["\u{0644}\u{0644}\u{0644}\u{0644}"]
        #expect(isPersian("gggg", engine: engine))
    }

    @Test("A protected English word is never converted")
    func protectedEnglishWord() throws {
        let engine = try makeEngine()
        engine.lexicon.protectedEnglish = ["fun"]
        #expect(!isPersian("fun", engine: engine))
    }

    // MARK: - Persian text helpers

    @Test("The lookup key drops the zero width non-joiner")
    func lookupKeyDropsZWNJ() {
        #expect(PersianText.lookupKey("می\u{200C}رود") == "میرود")
        #expect(PersianText.containsZeroWidthNonJoiner("کتاب\u{200C}ها"))
        #expect(!PersianText.containsZeroWidthNonJoiner("کتابها"))
    }

    // MARK: - Whole passages

    @Test("A passage is converted word by word")
    func passageConversion() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("sghl ;jhf") == "سلام کتاب")
        #expect(engine.convertText("hello sghl") == "hello سلام")
    }

    @Test("A passage keeps its spacing and punctuation")
    func passageKeepsEverythingElse() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("sghl, ;jhf!") == "سلام, کتاب!")
        #expect(engine.convertText("hello\nworld") == "hello\nworld")
        #expect(engine.convertText("") == "")
    }

    @Test("Persian text is left alone")
    func passageKeepsPersian() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("سلام دنیا") == "سلام دنیا")
    }

    // MARK: - Single letters, function words and disambiguation

    @Test("Standalone single Persian letters convert properly", arguments: [
        (",", "و"), (";", "ک"), ("'", "گ"), ("[", "ج"), ("]", "چ"),
        ("h", "ا"), ("f", "ب"), ("n", "د"), ("l", "م"), ("d", "ی"),
        ("j", "ت"), ("k", "ن"), ("s", "س"), ("v", "ر"), ("c", "ز"),
        ("g", "ل"), ("p", "ح"), ("t", "ف"), ("r", "ق"), ("e", "ث"),
        ("w", "ص"), ("q", "ض"), ("x", "ط"), ("z", "ظ"), ("b", "ذ"),
        ("m", "پ"),
    ])
    func standaloneSingleLetters(latin: String, persian: String) throws {
        let engine = try makeEngine()
        #expect(convert(latin, engine: engine) == persian)
    }

    @Test("Single letters inside Persian context convert including alef/heh/sheen")
    func singleLettersInPersianContext() throws {
        let engine = try makeEngine()
        let ctx = ConversionContext(previousWasPersian: true, sentenceLanguage: .persian)
        #expect(convert("a", context: ctx, engine: engine) == "ش")
        #expect(convert("i", context: ctx, engine: engine) == "ه")
        #expect(convert("d", context: ctx, engine: engine) == "ی")
        #expect(convert("h", context: ctx, engine: engine) == "ا")
    }

    @Test("Standalone a and i remain English outside Persian context")
    func singleLettersInEnglishContext() throws {
        let engine = try makeEngine()
        #expect(convert("a", engine: engine) == "a")
        #expect(convert("i", engine: engine) == "i")
        let ctx = ConversionContext(previousWasPersian: false, sentenceLanguage: .english)
        #expect(convert("x", context: ctx, engine: engine) == "x")
        #expect(convert("b", context: ctx, engine: engine) == "b")
    }

    @Test("Common function and short Persian words are always converted", arguments: [
        ("d;", "یک"),
        ("fi", "به"),
        (",", "و"),
        ("h,", "او"),
        ("]i", "چه"),
        ("],", "چو"),
        ("],k", "چون"),
        (";d", "کی"),
        (";,", "کو"),
        ("h'v", "اگر"),
        ("l'v", "مگر"),
        ("'v", "گر"),
        ("fv", "بر"),
        ("fd", "بی"),
        ("id", "هی"),
        ("hd", "ای"),
        ("hi", "اه"),
        ("ni", "ده"),
        ("nd", "دی"),
        ("nl", "دم"),
        ("mv", "پر"),
        ("mh", "پا"),
        ("md", "پی"),
        ("mg", "پل"),
        ("li", "مه"),
        ("af", "شب"),
        ("sv", "سر"),
        ("pn", "حد"),
        ("pr", "حق"),
        ("pg", "حل"),
        ("ps", "حس"),
        ("ol", "خم"),
        ("cv", "زر"),
        ("vs", "رس"),
        ("vi", "ره"),
        ("fs", "بس"),
        ("fg", "بل"),
        ("s'", "سگ"),
        ("id]", "هیچ"),
        ("mk[", "پنج"),
        ("d;d", "یکی"),
        ("d;fhv", "یکبار"),
        ("d;nd'v", "یکدیگر"),
    ])
    func persianFunctionAndShortWords(latin: String, persian: String) throws {
        let engine = try makeEngine()
        #expect(convert(latin, engine: engine) == persian)
    }

    @Test("Persian words convert cleanly in sentences and after English words")
    func phrasesWithShortWords() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("d; ;jhf") == "یک کتاب")
        #expect(engine.convertText("fi khl onh") == "به نام خدا")
        #expect(engine.convertText("lk , j,") == "من و تو")
        #expect(engine.convertText("fd ;jhf") == "بی کتاب")
        #expect(engine.convertText("mv hc") == "پر از")
        #expect(engine.convertText("sv ;hv") == "سر کار")
        #expect(engine.convertText("af fodv") == "شب بخیر")
        #expect(engine.convertText("hello d;") == "hello یک")
        #expect(engine.convertText("hello fi") == "hello به")
        #expect(engine.convertText("1 d;") == "1 یک")
        #expect(engine.convertText("1 fi 2") == "1 به ۲")
    }

    @Test("Ambiguous words convert inside Persian sentences")
    func ambiguousInPersianSentence() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("sghl an") == "سلام شد")
        #expect(engine.convertText("sghl fun") == "سلام بعد")
        #expect(engine.convertText("sghl leg") == "سلام مثل")
        #expect(engine.convertText("sghl 1 an") == "سلام ۱ شد")
    }
    // MARK: - The language of the sentence

    @Test("Persian words without an English equivalent are always Persian", arguments: [
        ("hc", "از"), ("fi", "به"), ("dh", "یا"), ("nv", "در"),
        ("iv", "هر"), ("ms", "پس"), ("il", "هم"), ("jh", "تا"),
        ("fh", "با"), ("ld", "می"), ("lk", "من"), ("lh", "ما"),
        ("ki", "نه"), ("si", "سه"), ("ng", "دل"), ("hf", "اب"),
    ])
    func persianOnlyWords(latin: String, persian: String) throws {
        let engine = try makeEngine()
        // At the start of a sentence…
        #expect(convert(latin, engine: engine) == persian)
        // …and inside an English sentence.
        let english = ConversionContext(previousWasPersian: false, sentenceLanguage: .english)
        #expect(convert(latin, context: english, engine: engine) == persian)
    }

    @Test("The first word decides the language of the sentence")
    func firstWordDecides() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("hc hdk ;jhf") == "از این کتاب")
        #expect(engine.convertText("hello fun") == "hello fun")
    }

    @Test("A Persian sentence keeps the English words that have no Persian equivalent")
    func persianSentenceKeepsEnglish() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("hc google") == "از google")
    }

    @Test("A Persian-only word switches an English sentence to Persian")
    func persianOnlyWordSwitchesSentence() throws {
        let engine = try makeEngine()
        #expect(engine.convertText("hello sghl") == "hello سلام")
        #expect(engine.convertText("hello sghl fun") == "hello سلام بعد")
    }

    @Test("An address makes the sentence English")
    func addressStartsAnEnglishSentence() throws {
        let engine = try makeEngine()
        let outcome = engine.resolve(token: "https://example.com", context: ConversionContext())
        #expect(outcome.context.sentenceLanguage == .english)
        #expect(engine.convertText("https://example.com sghl") == "https://example.com سلام")
    }

    @Test("An ambiguous word decides nothing")
    func ambiguousWordDecidesNothing() throws {
        let engine = try makeEngine()
        let outcome = engine.resolve(token: "fun", context: ConversionContext())
        #expect(outcome.context.sentenceLanguage == .unknown)
    }

    @Test("A trailing comma stays with the word it follows")
    func trailingCommaStaysWithItsWord() throws {
        let engine = try makeEngine()
        let persian = ConversionContext(previousWasPersian: true, sentenceLanguage: .persian)
        let english = ConversionContext(previousWasPersian: false, sentenceLanguage: .english)
        #expect(convert("sghl,", context: persian, engine: engine) == "سلام,")
        #expect(convert("hello,", context: english, engine: engine) == "hello,")
    }

    @Test("The question mark and the percent sign have Persian forms")
    func persianPunctuationMarks() {
        #expect(PersianText.persianPunctuationMark(for: "?") == "؟")
        #expect(PersianText.persianPunctuationMark(for: "%") == "٪")
        #expect(PersianText.persianPunctuationMark(for: "a") == nil)
    }
}
