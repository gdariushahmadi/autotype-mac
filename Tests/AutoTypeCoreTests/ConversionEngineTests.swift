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
}
