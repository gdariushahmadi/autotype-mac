import Foundation
import Testing
@testable import AutoTypeCore

@Suite("Language from word prefixes")
struct PrefixLanguageTests {
    @Test("An exclusive prefix selects a language and follows the word")
    func exclusivePrefixes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persian = directory.appendingPathComponent("persian.tsv")
        let english = directory.appendingPathComponent("english.txt")
        let common = directory.appendingPathComponent("common.txt")
        try "سلاله\t\t1\nسلام\t\t1\n".write(to: persian, atomically: true, encoding: .utf8)
        try "hello\nsghabc\n".write(to: english, atomically: true, encoding: .utf8)
        try "hello\n".write(to: common, atomically: true, encoding: .utf8)
        let lexicon = try Lexicon(persianURL: persian, englishURL: english, englishCommonURL: common)
        var settings = ConversionSettings()
        settings.fixTransposedCharacters = false
        let engine = ConversionEngine(lexicon: lexicon, settings: settings)

        let englishPrefix = engine.resolve(token: "helx")
        #expect(englishPrefix.output == "helx")
        #expect(englishPrefix.context.sentenceLanguage == .english)
        let persianPrefix = engine.resolve(token: "sghgx")
        #expect(persianPrefix.output == "سلالط")
        #expect(persianPrefix.context.sentenceLanguage == .persian)

        // The shorter prefix is in both lists, including after backspace.
        #expect(engine.resolve(token: "sgh").context.sentenceLanguage == .unknown)
        #expect(engine.resolve(token: "he").context.sentenceLanguage == .unknown)
        #expect(engine.resolve(token: "zzz").context.sentenceLanguage == .unknown)
        #expect(engine.resolve(token: "hello").output == "hello")
        #expect(engine.resolve(token: "sghl").output == "سلام")

        // User dictionaries are included in prefix searches.
        lexicon.protectedEnglish = ["zebra"]
        lexicon.personalPersian = ["طظظظ"]
        #expect(lexicon.containsEnglishPrefix("ZEB"))
        #expect(lexicon.containsPersianPrefix("طظظ"))

        settings.lockLanguageFromSentenceStart = false
        engine.settings = settings
        #expect(engine.resolve(token: "helx").context.sentenceLanguage == .unknown)
    }
}
