import Foundation

/// Persian orthography helpers: canonicalisation, ZWNJ, punctuation, digits and
/// the clitics (plural / possessive suffixes and the `می`/`نمی` prefixes) that
/// Persian attaches directly to a word.
public enum PersianText {

    public static let zeroWidthNonJoiner: Character = "\u{200C}"
    public static let zeroWidthJoiner: Character = "\u{200D}"

    private static let arabicYeh: Character = "ي"
    private static let farsiYeh: Character = "ی"
    private static let arabicKaf: Character = "ك"
    private static let farsiKaf: Character = "ک"
    private static let tatweel: Character = "ـ"
    private static let hehWithYehAbove: Character = "ۀ"
    private static let hehGoal: Character = "ہ"
    private static let alefMadda: Character = "آ"

    /// Normalises Persian spelling so that dictionary lookups are stable.
    ///
    /// Arabic yeh/kaf are folded onto their Persian counterparts, tatweel is
    /// dropped, and the ZWNJ is preserved (it is meaningful) — use
    /// `lookupKey` when a ZWNJ-insensitive comparison is wanted.
    public static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case arabicYeh: result.append(farsiYeh)
            case arabicKaf: result.append(farsiKaf)
            case tatweel: break
            case hehWithYehAbove: result.append("ه"); result.append(zeroWidthNonJoiner)
            case hehGoal: result.append("ه")
            default: result.append(character)
            }
        }
        return result
    }

    /// Removes every invisible joiner so two spellings compare equal.
    ///
    /// The joiners are handled as Unicode scalars, not as `Character`s: U+200C
    /// is a grapheme-extend code point, so in Swift it is glued to the letter
    /// in front of it (`"می\u{200C}رود"` has five characters, not six) and a
    /// character-level filter would never see it.
    public static func stripJoiners(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value == 0x200C || scalar.value == 0x200D { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// `true` when the text contains a zero width non-joiner.
    ///
    /// Scalar-based for the same reason as `stripJoiners`.
    public static func containsZeroWidthNonJoiner(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value == 0x200C }
    }

    /// The key used for dictionary lookups: normalised and ZWNJ-free.
    public static func lookupKey(_ text: String) -> String {
        stripJoiners(normalize(text))
    }

    // MARK: - Digits

    private static let persianDigits: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

    /// Converts ASCII digits inside a string to Persian digits.
    public static func persianDigits(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if character.isASCII, character.isNumber,
               let ascii = character.asciiValue, ascii >= 48, ascii <= 57 {
                result.append(persianDigits[Int(ascii - 48)])
            } else {
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Punctuation

    /// ASCII punctuation → its Persian counterpart.
    private static let persianPunctuation: [Character: Character] = [
        ",": "،",   // ARABIC COMMA
        ";": "؛",   // ARABIC SEMICOLON
        "?": "؟",   // ARABIC QUESTION MARK
        "%": "٪",   // ARABIC PERCENT SIGN
    ]

    /// Rewrites ASCII punctuation as Persian punctuation.
    ///
    /// The `،` and `؛` cases are the important ones: a Persian sentence should
    /// not end up mixing `,` with `،`.
    public static func persianPunctuation(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            result.append(persianPunctuation[character] ?? character)
        }
        return result
    }

    /// The Persian counterpart of an ASCII punctuation mark, when there is one.
    public static func persianPunctuationMark(for character: Character) -> Character? {
        persianPunctuation[character]
    }

    // MARK: - Clitics

    /// Suffixes Persian attaches straight onto a noun.
    ///
    /// Only the suffixes that are always written with a ZWNJ are listed. The
    /// enclitic pronouns (`م`, `ت`, `ی`, `ام`, `ات`, `اش`) attach directly and
    /// take no ZWNJ, so guessing where they belong would produce the wrong
    /// spelling — and they are rare enough in running text not to be worth the
    /// risk of mistaking an English word for one.
    public static let suffixes: [String] = [
        "های", "ها", "تر",
    ]

    /// Prefixes Persian attaches straight onto a verb.
    ///
    /// `می` and `نمی` are always written with a ZWNJ (`می‌رود`, `نمی‌دانم`).
    /// The negative `ن` is not: it attaches directly (`نرفت`).
    public static let prefixes: [String] = ["نمی", "می"]

    /// Splits a Persian string into `stem` + `suffix` when the suffix is a
    /// known clitic and the stem is long enough to stand on its own.
    ///
    /// The returned suffix is joined with a ZWNJ, which is the correct Persian
    /// spelling for these forms (`کتاب‌ها`, `بزرگ‌تر`).
    public static func splitCliticSuffix(_ persian: String) -> (stem: String, suffix: String)? {
        guard persian.count >= 3 else { return nil }
        for suffix in suffixes {
            guard persian.hasSuffix(suffix) else { continue }
            let stem = String(persian.dropLast(suffix.count))
            guard stem.count >= 2 else { continue }
            return (stem, suffix)
        }
        return nil
    }

    /// Splits a Persian string into `prefix` + `stem` for the `می`/`نمی` verbs.
    public static func splitCliticPrefix(_ persian: String) -> (prefix: String, stem: String)? {
        for prefix in prefixes {
            guard persian.hasPrefix(prefix) else { continue }
            let stem = String(persian.dropFirst(prefix.count))
            guard stem.count >= 2 else { continue }
            return (prefix, stem)
        }
        return nil
    }

    /// `true` when the character is a Persian letter.
    public static func isPersianLetter(_ character: Character) -> Bool {
        PersianLayout.persianLetters.contains(character)
    }

    /// `true` when the text contains at least one Persian letter or Persian Unicode character.
    public static func containsPersian(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (scalar.value >= 0x0600 && scalar.value <= 0x06FF) ||
            (scalar.value >= 0xFB50 && scalar.value <= 0xFDFF) ||
            (scalar.value >= 0xFE70 && scalar.value <= 0xFEFF)
        }
    }
}
