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
        settings.checkForForbiddenWords = true
        settings.forbiddenWordsAction = .block

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
        #expect(settings.defaultLanguage == .persian)
        #expect(settings.englishModifier == .rightCommand)
        #expect(settings.usePersianPunctuation == true)
        #expect(settings.fixPunctuationSpacing == true)
        #expect(settings.checkForForbiddenWords == true)
        #expect(settings.forbiddenWordsAction == .requireConfirmation)
    }

    @Test("A dictionary that is missing a key keeps the words it has")
    func partialDictionary() throws {
        let data = Data(#"{"persianWords": ["سلام"], "forbiddenWords": ["محرمانه"]}"#.utf8)
        let dictionary = try JSONDecoder().decode(PersonalDictionary.self, from: data)
        #expect(dictionary.persianWords == ["سلام"])
        #expect(dictionary.englishWords.isEmpty)
        #expect(dictionary.forbiddenWords == ["محرمانه"])
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

    @Test("Disabled apps list is checked case-insensitively")
    func disabledAppsCheck() {
        var settings = ConversionSettings()
        settings.disabledApps = ["com.apple.Terminal", "com.microsoft.VSCode"]

        #expect(settings.isAppDisabled(bundleID: "com.apple.Terminal"))
        #expect(settings.isAppDisabled(bundleID: "COM.APPLE.TERMINAL"))
        #expect(settings.isAppDisabled(bundleID: "com.microsoft.vscode"))
        #expect(!settings.isAppDisabled(bundleID: "org.telegram.desktop"))
        #expect(!settings.isAppDisabled(bundleID: nil))
        #expect(!settings.isAppDisabled(bundleID: ""))
    }
}
