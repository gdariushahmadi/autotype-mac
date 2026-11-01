import Testing
import Foundation
@testable import AutoTypeCore

@Suite("Forbidden Words")
struct ForbiddenWordsTests {

    @Test("Detects single Persian forbidden word")
    func singlePersianWord() {
        let forbidden = ["محرمانه"]
        let text = "این یک متن محرمانه است."
        let matches = ForbiddenWordsDetector.findMatches(in: text, forbiddenWords: forbidden)
        #expect(matches == ["محرمانه"])
    }

    @Test("Detects single English forbidden word")
    func singleEnglishWord() {
        let forbidden = ["password", "secret"]
        let text = "Please enter your password here"
        let matches = ForbiddenWordsDetector.findMatches(in: text, forbiddenWords: forbidden)
        #expect(matches == ["password"])
    }

    @Test("Detects multi-word forbidden phrase")
    func multiWordPhrase() {
        let forbidden = ["رمز عبور", "اطلاعات حساس"]
        let text = "رمز عبور خود را به کسی ندهید"
        let matches = ForbiddenWordsDetector.findMatches(in: text, forbiddenWords: forbidden)
        #expect(matches == ["رمز عبور"])
    }

    @Test("Does not false-positive on substrings of other words")
    func avoidsFalsePositives() {
        let forbidden = ["خر", "pass"]
        let text = "خرید کتاب در خرداد ماه با compass انجام شد"
        let matches = ForbiddenWordsDetector.findMatches(in: text, forbiddenWords: forbidden)
        #expect(matches.isEmpty)
    }

    @Test("Handles Persian clitics and ZWNJ")
    func persianCliticsAndZWNJ() {
        let forbidden = ["بی‌شعور", "احمق"]
        // Word with ZWNJ vs without ZWNJ
        let text1 = "واقعا بیشعور هستی"
        #expect(ForbiddenWordsDetector.findMatches(in: text1, forbiddenWords: forbidden) == ["بی‌شعور"])

        // Word with plural clitic suffix
        let text2 = "این احمق‌ها را ببین"
        #expect(ForbiddenWordsDetector.findMatches(in: text2, forbiddenWords: forbidden) == ["احمق"])

        // Word with attached pronoun
        let text3 = "به آن احمقها بگو"
        #expect(ForbiddenWordsDetector.findMatches(in: text3, forbiddenWords: forbidden) == ["احمق"])
    }

    @Test("Normalizes Arabic letters in forbidden words")
    func arabicYehAndKaf() {
        let forbidden = ["بانك", "اطلاعاتي"] // Arabic kaf and yeh
        let text = "اطلاعاتی بانک ملی"      // Persian kaf and yeh
        let matches = ForbiddenWordsDetector.findMatches(in: text, forbiddenWords: forbidden)
        #expect(matches.count == 2)
    }

    @Test("Returns empty when text has no forbidden words")
    func cleanText() {
        let forbidden = ["محرمانه", "password"]
        let text = "سلام روز خوبی داشته باشید"
        let matches = ForbiddenWordsDetector.findMatches(in: text, forbiddenWords: forbidden)
        #expect(matches.isEmpty)
    }
}
