import Foundation
import AutoTypeCore

/// A small assertion runner.
///
/// The Command Line Tools toolchain cannot run `swift test`, so the same
/// checks live here as a plain executable: `swift run AutoTypeChecks`.
struct Checker {
    private var failures: [String] = []
    private var checks = 0
    private var currentGroup = ""

    mutating func group(_ name: String) {
        currentGroup = name
        print("\n▸ \(name)")
    }

    mutating func expect(_ condition: Bool, _ description: String) {
        checks += 1
        if condition {
            print("  ✓ \(description)")
        } else {
            print("  ✗ \(description)")
            failures.append("\(currentGroup): \(description)")
        }
    }

    mutating func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ description: String
    ) {
        checks += 1
        if actual == expected {
            print("  ✓ \(description)")
        } else {
            print("  ✗ \(description)")
            print("      expected: \(expected)")
            print("      actual:   \(actual)")
            failures.append("\(currentGroup): \(description) — expected \(expected), got \(actual)")
        }
    }

    func report() -> Int32 {
        print("\n" + String(repeating: "─", count: 60))
        if failures.isEmpty {
            print("All \(checks) checks passed.")
            return 0
        }
        print("\(failures.count) of \(checks) checks failed:")
        for failure in failures { print("  • \(failure)") }
        return 1
    }
}

var checker = Checker()

// MARK: - Layout

checker.group("Keyboard layout (ISIRI 2901)")

checker.expectEqual(PersianLayout.convert("sghl"), "سلام", "sghl → سلام")
checker.expectEqual(PersianLayout.convert("asdfghjkl"), "شسیبلاتنم", "home row")
checker.expectEqual(PersianLayout.convert("qwertyuiop"), "ضصثقفغعهخح", "top row")
checker.expectEqual(PersianLayout.convert("zxcvbnm,"), "ظطزرذدپو", "bottom row")
checker.expectEqual(PersianLayout.convert(";jh"), "کتا", "punctuation keys carry letters")
checker.expectEqual(PersianLayout.persianOnlyKeys, ["[", "]", ";", "'", ","], "Persian-only keys")
checker.expect(PersianLayout.convert("hello1") == nil, "digits have no Persian form")
checker.expect(PersianLayout.containsInteriorPersianOnlyKey("o,f"), "interior Persian-only key detected")
checker.expect(!PersianLayout.containsInteriorPersianOnlyKey("hello,"), "trailing comma is punctuation")

// MARK: - Engine

let engine: ConversionEngine
do {
    engine = ConversionEngine(lexicon: try AutoTypeResources.loadLexicon())
} catch {
    print("Could not load the dictionaries: \(error)")
    exit(1)
}

func convert(_ token: String, context: ConversionContext = ConversionContext()) -> String {
    engine.decide(token: token, context: context).output
}

func isPersian(_ token: String, context: ConversionContext = ConversionContext()) -> Bool {
    if case .convertToPersian = engine.decide(token: token, context: context) { return true }
    return false
}

checker.group("Persian words")

checker.expectEqual(convert("sghl"), "سلام", "sghl → سلام")
checker.expectEqual(convert(";jhf"), "کتاب", ";jhf → کتاب")
checker.expectEqual(convert("ldv,n"), "می\u{200C}رود", "ldv,n → می‌رود")
checker.expectEqual(convert("khnj"), "نادت", "a non-English token converts to Persian")
checker.expectEqual(convert("o,f"), "خوب", "o,f → خوب")
checker.expectEqual(convert(";jhfih"), "کتاب\u{200C}ها", "the plural keeps its ZWNJ")

checker.group("English words")

for word in ["hello", "the", "world", "code", "swift", "apple", "system", "input", "method"] {
    checker.expectEqual(convert(word), word, "\(word) is left alone")
}
checker.expectEqual(convert("hello,"), "hello,", "trailing comma is kept")
checker.expectEqual(convert("don't"), "don't", "contraction is protected")
checker.expectEqual(convert("it's"), "it's", "contraction is protected")

checker.group("Technical strings")

for token in [
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
    "123",
    "2024",
] {
    checker.expectEqual(convert(token), token, "\(token) is left alone")
}

checker.group("Ambiguity")

checker.expect(!isPersian("fun"), "ambiguous word defaults to English")
checker.expect(
    isPersian("fun", context: ConversionContext(previousWasPersian: true, previousPersianWord: "سلام")),
    "ambiguous word follows Persian context"
)

checker.group("Whole passages")

checker.expectEqual(engine.convertText("sghl ;jhf"), "سلام کتاب", "a passage is converted word by word")
checker.expectEqual(engine.convertText("hello sghl"), "hello سلام", "an English word in a passage is left alone")
checker.expectEqual(engine.convertText("sghl, ;jhf!"), "سلام, کتاب!", "punctuation is kept")
checker.expectEqual(engine.convertText("سلام دنیا"), "سلام دنیا", "Persian text is left alone")
checker.expectEqual(engine.convertText("می\u{200C}رود"), "می\u{200C}رود", "Persian text with a ZWNJ is left alone")

checker.group("Latinizing")

checker.expectEqual(PersianLayout.latinize("سلام"), "sghl", "سلام → sghl")
checker.expectEqual(PersianLayout.latinize("کتاب"), ";jhf", "کتاب → ;jhf")
checker.expectEqual(PersianLayout.latinize("سلام دنیا"), "sghl nkdh", "a sentence keeps its space")
checker.expectEqual(PersianLayout.latinize("می\u{200C}رود"), "ld v,n", "the zero width non-joiner becomes a space")
checker.expectEqual(PersianLayout.latinize("hello 123"), "hello 123", "Latin text is left alone")


engine.settings.priority = .persianFirst
checker.expect(isPersian("fun"), "Persian-first priority converts the homograph")
engine.settings.priority = .englishFirst
checker.expect(!isPersian("fun"), "English-first priority keeps the homograph")
engine.settings.priority = .automatic

checker.group("Personal dictionary")

engine.lexicon.personalPersian = ["\u{0644}\u{0644}\u{0644}\u{0644}"]
checker.expect(isPersian("gggg"), "a personal Persian word always converts")
engine.lexicon.personalPersian = []
engine.lexicon.protectedEnglish = ["fun"]
checker.expect(!isPersian("fun"), "a protected English word is never converted")
engine.lexicon.protectedEnglish = []

checker.group("Phonotactics")

checker.expect(PersianPhonotactics.looksPersian("سلام"), "a Persian word passes the shape check")
checker.expect(!PersianPhonotactics.looksPersian("abc"), "a Latin word fails the shape check")
checker.expect(!PersianPhonotactics.looksPersian("تتتتت"), "a repeated consonant run fails")

checker.group("Persian text helpers")

checker.expectEqual(PersianText.lookupKey("می\u{200C}رود"), "میرود", "the lookup key drops the ZWNJ")
checker.expect(PersianText.containsZeroWidthNonJoiner("کتاب\u{200C}ها"), "a ZWNJ is detected")
checker.expect(!PersianText.containsZeroWidthNonJoiner("کتابها"), "no ZWNJ is reported when there is none")
checker.expectEqual(PersianText.normalize("ي"), "ی", "Arabic yeh folds to Persian yeh")
checker.expectEqual(PersianText.persianDigits("1403"), "۱۴۰۳", "digits convert to Persian numerals")
checker.expectEqual(PersianText.persianPunctuation("سلام، خوب؟"), "سلام، خوب؟", "Persian punctuation is kept")

checker.group("Settings round-trip")

var settings = ConversionSettings()
settings.mode = .directPersian
settings.priority = .persianFirst
settings.usePersianDigits = true
settings.englishModifier = .rightOption
let encoded = try JSONEncoder().encode(settings)
let decoded = try JSONDecoder().decode(ConversionSettings.self, from: encoded)
checker.expectEqual(decoded, settings, "settings survive a JSON round trip")

// A settings file that is missing a key — written by an older version, or
// edited by hand — must keep the keys it does have.
let partial = Data(#"{"mode": "directPersian"}"#.utf8)
if let partialSettings = try? JSONDecoder().decode(ConversionSettings.self, from: partial) {
    checker.expectEqual(partialSettings.mode, .directPersian, "a partial settings file keeps the keys it has")
    checker.expectEqual(partialSettings.priority, .automatic, "a partial settings file falls back to the defaults")
} else {
    checker.expect(false, "a partial settings file is decoded")
}

let partialDictionary = Data(#"{"persianWords": ["سلام"]}"#.utf8)
if let partialWords = try? JSONDecoder().decode(PersonalDictionary.self, from: partialDictionary) {
    checker.expectEqual(partialWords.persianWords, ["سلام"], "a partial dictionary keeps the words it has")
    checker.expectEqual(partialWords.englishWords, [], "a partial dictionary falls back to an empty list")
} else {
    checker.expect(false, "a partial dictionary is decoded")
}

checker.group("Translation trigger prefix")

var trSettings = TranslationSettings(isEnabled: true, requireTriggerPrefix: true, triggerPrefix: "ترجمه")
checker.expectEqual(trSettings.extractTranslatableBody(from: "ترجمه سلام دنیا"), "سلام دنیا", "extracts text after Persian trigger word")
checker.expectEqual(trSettings.extractTranslatableBody(from: "ترجمه: سلام دنیا"), "سلام دنیا", "extracts text after trigger word with colon")
checker.expect(trSettings.extractTranslatableBody(from: "سلام دنیا") == nil, "ignores sentence without trigger word when prefix required")
trSettings.requireTriggerPrefix = false
checker.expectEqual(trSettings.extractTranslatableBody(from: "سلام دنیا"), "سلام دنیا", "translates any Persian sentence when prefix is not required")

checker.group("Sentence language locking")
let ctxPersian = ConversionContext(previousWasPersian: true, sentenceLanguageIsPersian: true)
let ctxEnglish = ConversionContext(previousWasPersian: false, sentenceLanguageIsPersian: false)
// "fun" converts to Persian "بعد" (f->ب, u->ع, n->د)
checker.expectEqual(engine.decide(token: "fun", context: ctxPersian), .convertToPersian("بعد"), "locks to Persian when sentence started with Persian")
checker.expectEqual(engine.decide(token: "fun", context: ctxEnglish), .keepAsTyped("fun"), "locks to English when sentence started with English")
checker.expectEqual(engine.decide(token: ";jhf\u{200C}ih", context: ctxPersian), .convertToPersian("کتاب‌ها"), "converts word containing ZWNJ cleanly to Persian")

checker.group("Typo and Enter Interception Guard")
let badText = "این پروژع با موفغیت انجلم شود"
let analysis = TypoDetector.analyze(badText)
checker.expect(analysis.hasSuspiciousTokens, "flags suspicious typos in sentence")
checker.expectEqual(analysis.suggestions["پروژع"], "پروژه", "suggests correct spelling for پروژع")
checker.expectEqual(analysis.suggestions["موفغیت"], "موفقیت", "suggests correct spelling for موفغیت")
checker.expectEqual(analysis.suggestions["انجلم"], "انجام", "suggests correct spelling for انجلم")

let cleanText = "این پروژه با موفقیت انجام شد"
let cleanAnalysis = TypoDetector.analyze(cleanText)
checker.expect(!cleanAnalysis.hasSuspiciousTokens, "passes clean Persian sentence without false alerts")

exit(checker.report())
