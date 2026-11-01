import Testing
import Foundation
@testable import AutoTypeCore

@Suite("Settings")
struct SettingsTests {

    @Test("Settings survive a JSON round trip")
    func roundTrip() throws {
        var settings = ConversionSettings()
        settings.mode = .directPersian
        settings.priority = .persianFirst
        settings.usePersianDigits = true
        settings.usePersianPunctuation = false
        settings.englishModifier = .rightOption

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ConversionSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("A settings file that is missing a key keeps the keys it has")
    func partialSettings() throws {
        let data = Data(#"{"mode": "directPersian"}"#.utf8)
        let settings = try JSONDecoder().decode(ConversionSettings.self, from: data)
        #expect(settings.mode == .directPersian)
        #expect(settings.priority == .automatic)
        #expect(settings.englishModifier == .rightCommand)
        #expect(settings.usePersianPunctuation == true)
    }

    @Test("A dictionary that is missing a key keeps the words it has")
    func partialDictionary() throws {
        let data = Data(#"{"persianWords": ["سلام"]}"#.utf8)
        let dictionary = try JSONDecoder().decode(PersonalDictionary.self, from: data)
        #expect(dictionary.persianWords == ["سلام"])
        #expect(dictionary.englishWords.isEmpty)
    }

    @Test("Persian punctuation is written in Persian")
    func persianPunctuation() {
        #expect(PersianText.persianPunctuation("سلام، خوب؟") == "سلام، خوب؟")
        #expect(PersianText.persianPunctuation("hello, world?") == "hello، world؟")
        #expect(PersianText.persianPunctuationMark(for: ",") == "،")
        #expect(PersianText.persianPunctuationMark(for: ".") == nil)
    }

    @Test("Digits are converted to Persian numerals")
    func persianDigits() {
        #expect(PersianText.persianDigits("1403") == "۱۴۰۳")
        #expect(PersianText.persianDigits("a1b2") == "a۱b۲")
    }
}
