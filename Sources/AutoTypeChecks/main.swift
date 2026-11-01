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
checker.expectEqual(PersianText.persianDigit(for: "5"), "۵", "single digit converts to Persian numeral")
checker.expectEqual(PersianText.persianPunctuation("سلام، خوب؟"), "سلام، خوب؟", "Persian punctuation is kept")

checker.group("Smart contextual numbers")

do {
    var smartSettings = ConversionSettings()
    smartSettings.usePersianDigits = true
    let smartEngine = ConversionEngine(lexicon: engine.lexicon, settings: smartSettings)

    // 1. At start (no context) -> English
    let atStart = smartEngine.resolve(token: "1403", context: ConversionContext())
    checker.expectEqual(atStart.output, "1403", "number at start stays English")
    checker.expect(atStart.context.sentenceLanguage != SentenceLanguage.english, "number at start does not lock sentence to English")

    // 2. Next Persian word after initial number converts to Persian
    let afterNum = smartEngine.resolve(token: ";jhf", context: atStart.context)
    checker.expectEqual(afterNum.output, "کتاب", "Persian word after starting number converts to Persian")

    // 3. Inside Persian context -> Persian numerals
    let inPersianContext = ConversionContext(previousWasPersian: true, previousPersianWord: "سلام", sentenceLanguage: .persian)
    let insidePersian = smartEngine.resolve(token: "1403", context: inPersianContext)
    checker.expectEqual(insidePersian.output, "۱۴۰۳", "number inside Persian text becomes Persian numerals")

    // 4. Inside English context -> English digits
    let inEnglishContext = ConversionContext(previousWasPersian: false, sentenceLanguage: .english)
    let insideEnglish = smartEngine.resolve(token: "1403", context: inEnglishContext)
    checker.expectEqual(insideEnglish.output, "1403", "number inside English text stays English")

    // 5. When disabled -> English digits everywhere
    var offSettings = ConversionSettings()
    offSettings.usePersianDigits = false
    let offEngine = ConversionEngine(lexicon: engine.lexicon, settings: offSettings)
    let disabledInsidePersian = offEngine.resolve(token: "1403", context: inPersianContext)
    checker.expectEqual(disabledInsidePersian.output, "1403", "number inside Persian text stays English when option is disabled")
}

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
let ctxPersian = ConversionContext(previousWasPersian: true, sentenceLanguage: .persian)
let ctxEnglish = ConversionContext(previousWasPersian: false, sentenceLanguage: .english)
// "fun" converts to Persian "بعد" (f->ب, u->ع, n->د)
checker.expectEqual(engine.decide(token: "fun", context: ctxPersian), .convertToPersian("بعد"), "locks to Persian when sentence started with Persian")
checker.expectEqual(engine.decide(token: "fun", context: ctxEnglish), .keepAsTyped("fun"), "locks to English when sentence started with English")
checker.expectEqual(engine.decide(token: ";jhf\u{200C}ih", context: ctxPersian), .convertToPersian("کتاب‌ها"), "converts word containing ZWNJ cleanly to Persian")

checker.group("Function words and single letters")
checker.expectEqual(convert("d;"), "یک", "d; → یک")
checker.expectEqual(convert("fi"), "به", "fi → به")
checker.expectEqual(convert(","), "و", ", → و")
checker.expectEqual(convert("h,"), "او", "h, → او")
checker.expectEqual(convert("]i"), "چه", "]i → چه")
checker.expectEqual(convert("fd"), "بی", "fd → بی")
checker.expectEqual(convert("d"), "ی", "single letter d → ی")
checker.expectEqual(convert("h"), "ا", "single letter h → ا")
checker.expectEqual(convert("f"), "ب", "single letter f → ب")
checker.expectEqual(convert("n"), "د", "single letter n → د")
checker.expectEqual(convert("l"), "م", "single letter l → م")
checker.expectEqual(convert("a", context: ctxPersian), "ش", "a inside Persian context → ش")
checker.expectEqual(convert("i", context: ctxPersian), "ه", "i inside Persian context → ه")
checker.expectEqual(convert("a"), "a", "standalone a outside Persian context → a")
checker.expectEqual(convert("i"), "i", "standalone i outside Persian context → i")
checker.expectEqual(engine.convertText("d; ;jhf"), "یک کتاب", "یک کتاب converts")
checker.expectEqual(engine.convertText("fi khl onh"), "به نام خدا", "به نام خدا converts")
checker.expectEqual(engine.convertText("lk , j,"), "من و تو", "من و تو converts")
checker.expectEqual(engine.convertText("fd ;jhf"), "بی کتاب", "بی کتاب converts")
checker.expectEqual(engine.convertText("mv hc"), "پر از", "پر از converts")
checker.expectEqual(engine.convertText("hello d;"), "hello یک", "d; after English converts to یک")
checker.expectEqual(engine.convertText("sghl an"), "سلام شد", "an in Persian sentence converts to شد")

checker.group("Persian words without an English equivalent")
// The everyday Persian function words whose Latin spelling is also an
// English entry (an abbreviation, a state code, a musical note). They have
// no English meaning, so they stay Persian wherever they stand.
for (latin, persian) in [("hc", "از"), ("fi", "به"), ("dh", "یا"), ("nv", "در"),
                         ("iv", "هر"), ("ms", "پس"), ("il", "هم"), ("jh", "تا"),
                         ("fh", "با"), ("ld", "می"), ("lk", "من"), ("lh", "ما"),
                         ("ki", "نه"), ("si", "سه"), ("ng", "دل"), ("hf", "اب")] {
    checker.expectEqual(engine.decide(token: latin), .convertToPersian(persian),
                        "\(latin) at the start of a sentence is «\(persian)»")
    checker.expectEqual(engine.decide(token: latin, context: ctxEnglish), .convertToPersian(persian),
                        "\(latin) inside an English sentence is still «\(persian)»")
}
// "of" is a real English word, so the sentence decides.
checker.expectEqual(engine.decide(token: "of", context: ctxPersian), .convertToPersian("خب"),
                    "«of» is «خب» inside a Persian sentence")
checker.expectEqual(engine.decide(token: "of", context: ctxEnglish), .keepAsTyped("of"),
                    "«of» stays English inside an English sentence")

checker.group("The first word decides the language of the sentence")
// A sentence that starts with Persian stays Persian.
checker.expectEqual(engine.convertText("hc hdk ;jhf"), "از این کتاب", "a Persian sentence stays Persian")
// A sentence that starts with English stays English.
checker.expectEqual(engine.convertText("hello fun"), "hello fun",
                    "a sentence that starts with English stays English")
checker.expectEqual(engine.convertText("hello sghl"), "hello سلام",
                    "a Persian-only word is the evidence that switches the sentence to Persian")
// …and the sentence follows the switch.
checker.expectEqual(engine.convertText("hello sghl fun"), "hello سلام بعد",
                    "the words after the switch are read as Persian")
// A Persian sentence keeps the English words that have no Persian equivalent.
checker.expectEqual(engine.convertText("hc google"), "از google",
                    "an English-only word stays English inside a Persian sentence")
// An address is English, and it decides the sentence like any other word.
checker.expectEqual(engine.convertText("www.google.com sghl"), "www.google.com سلام",
                    "an address does not turn the sentence into Persian")

checker.group("The context that the next word is judged in")
let afterPersian = engine.resolve(token: "hc", context: ConversionContext())
checker.expectEqual(afterPersian.context.sentenceLanguage, .persian, "a Persian-only word makes the sentence Persian")
checker.expectEqual(afterPersian.decision.output, "از", "the word itself is Persian")
let afterEnglish = engine.resolve(token: "hello", context: ConversionContext())
checker.expectEqual(afterEnglish.context.sentenceLanguage, .english, "an English-only word makes the sentence English")
let afterAmbiguous = engine.resolve(token: "fun", context: ConversionContext())
checker.expectEqual(afterAmbiguous.context.sentenceLanguage, .unknown, "an ambiguous word decides nothing")
let afterAddress = engine.resolve(token: "https://example.com", context: ConversionContext())
checker.expectEqual(afterAddress.context.sentenceLanguage, .english, "an address makes the sentence English")
let afterSwitch = engine.resolve(token: "sghl", context: ConversionContext(sentenceLanguage: .english))
checker.expectEqual(afterSwitch.context.sentenceLanguage, .persian, "a Persian-only word switches an English sentence")
checker.expectEqual(afterSwitch.decision.output, "سلام", "the word that carries the evidence is Persian")

checker.group("Punctuation")
// A trailing comma belongs to the word it follows, not to the word.
checker.expectEqual(engine.decide(token: "sghl,", context: ctxPersian), .convertToPersian("سلام,"),
                    "a trailing comma stays with the Persian word it follows")
checker.expectEqual(engine.decide(token: "hello,", context: ctxEnglish), .keepAsTyped("hello,"),
                    "a trailing comma stays with the English word it follows")
// The question mark and the percent sign are written the Persian way.
checker.expectEqual(PersianText.persianPunctuationMark(for: "?"), "؟", "? becomes ؟")
checker.expectEqual(PersianText.persianPunctuationMark(for: "%"), "٪", "% becomes ٪")
checker.expectEqual(PersianText.persianPunctuationMark(for: "a"), nil, "an ordinary letter has no Persian mark")

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

checker.group("Forbidden Words Detection & Send Interception")
let forbiddenList = ["محرمانه", "رمز عبور", "password", "احمق"]

let forbiddenText1 = "این یک گزارش کاملاً محرمانه است."
let matches1 = ForbiddenWordsDetector.findMatches(in: forbiddenText1, forbiddenWords: forbiddenList)
checker.expectEqual(matches1, ["محرمانه"], "finds Persian single forbidden word in sentence")

let forbiddenText2 = "لطفا رمز عبور را ارسال کنید"
let matches2 = ForbiddenWordsDetector.findMatches(in: forbiddenText2, forbiddenWords: forbiddenList)
checker.expectEqual(matches2, ["رمز عبور"], "finds multi-word forbidden phrase in sentence")

let forbiddenText3 = "My password is secure"
let matches3 = ForbiddenWordsDetector.findMatches(in: forbiddenText3, forbiddenWords: forbiddenList)
checker.expectEqual(matches3, ["password"], "finds English forbidden word in sentence")

let forbiddenText4 = "این احمق‌ها را نگاه کن"
let matches4 = ForbiddenWordsDetector.findMatches(in: forbiddenText4, forbiddenWords: forbiddenList)
checker.expectEqual(matches4, ["احمق"], "matches clitic plural variation of forbidden word")

let safeText = "خرید کتاب در خرداد ماه"
let safeMatches = ForbiddenWordsDetector.findMatches(in: safeText, forbiddenWords: ["خر"])
checker.expect(safeMatches.isEmpty, "does not falsely match substring in خرداد or خرید")

checker.group("Transposed character auto-correction (Persian & English)")
checker.expectEqual(convert("hkg'ds"), "انگلیس", "hkg'ds (انلگیس) → انگلیس")
checker.expectEqual(convert("hkg'dsd"), "انگلیسی", "hkg'dsd (انلگیسی) → انگلیسی")
checker.expectEqual(convert("انلگیس"), "انگلیس", "direct Persian انلگیس → انگلیس")
checker.expectEqual(convert("انلگیسی"), "انگلیسی", "direct Persian انلگیسی → انگلیسی")
checker.expectEqual(convert("fvklhi"), "برنامه", "fvklhi (برنماه) → برنامه")
checker.expectEqual(convert("tvhsd"), "فارسی", "tvhsd (فراسی) → فارسی")
checker.expectEqual(convert("sdjsl"), "سیستم", "sdjsl (سیتسم) → سیستم")
checker.expectEqual(convert("l,tdrj"), "موفقیت", "l,tdrj (موفیقت) → موفقیت")
checker.expectEqual(convert("shgl"), "سالم", "valid Persian word سالم is not turned into سلام")
checker.expectEqual(convert("teh"), "the", "teh → the")
checker.expectEqual(convert("Hte"), "The", "Hte → The (case preserved)")
checker.expectEqual(convert("adn"), "and", "adn → and")
checker.expectEqual(convert("recieve"), "receive", "recieve → receive")
checker.expectEqual(convert("freind"), "friend", "freind → friend")
checker.expectEqual(convert("enlgish"), "english", "enlgish → english")

exit(checker.report())
