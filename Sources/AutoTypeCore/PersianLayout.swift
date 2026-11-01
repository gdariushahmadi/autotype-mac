import Foundation

/// The standard Persian (Farsi) keyboard layout, ISIRI 2901.
///
/// AutoType keeps the physical keyboard on a US-QWERTY layout and maps every
/// key to the Persian letter that occupies the *same physical key position* on a
/// Persian layout. That is why `sghl` becomes `سلام`: `s`→س, `g`→ل, `h`→ا,
/// `l`→م.
///
/// The table below is the ISIRI 2901 layout that macOS ships as
/// “Persian-ISIRI 2901”, read straight out of the system keyboard layout
/// data:
///
/// ```
///   q w e r t y u i o p [ ]      ض ص ث ق ف غ ع ه خ ح ج چ
///   a s d f g h j k l ; '         ش س ی ب ل ا ت ن م ک گ
///   z x c v b n m ,                ظ ط ز ر ذ د پ و
/// ```
///
/// The mapping is data, not scattered constants, so a different physical layout
/// can be substituted without touching the conversion logic.
public enum PersianLayout {

    /// Latin key → Persian letter, for the ISIRI 2901 layout on QWERTY.
    public static let keyToPersian: [Character: Character] = [
        // Row 1
        "q": "ض", "w": "ص", "e": "ث", "r": "ق", "y": "غ", "t": "ف",
        "u": "ع", "i": "ه", "o": "خ", "p": "ح",
        "[": "ج", "]": "چ",
        // Row 2
        "a": "ش", "s": "س", "d": "ی", "f": "ب", "g": "ل",
        "h": "ا", "j": "ت", "k": "ن", "l": "م",
        ";": "ک", "'": "گ",
        // Row 3
        "z": "ظ", "x": "ط", "c": "ز", "v": "ر", "b": "ذ",
        "n": "د", "m": "پ", ",": "و",
    ]

    /// Shifted keys in Persian ISIRI 2901 layout on QWERTY.
    public static let shiftKeyToPersian: [Character: Character] = [
        "H": "آ",
        "C": "ژ",
        "M": "ء",
        "G": "أ",
        "F": "إ",
        "A": "ؤ",
        "D": "ي",
        "S": "ئ",
        "E": "ـ",
        "Y": "؛",
        "T": "،",
        "?": "؟",
    ]

    /// Keys that carry a Persian letter but are *not* Latin letters.
    ///
    /// Their presence inside a token is strong evidence that the author meant
    /// to write Persian: `گ` (apostrophe), `ک` (semicolon), `ج`/`چ` (brackets)
    /// and `و` (comma) essentially never appear inside an English word.
    public static let persianOnlyKeys: Set<Character> = ["[", "]", ";", "'", ","]

    /// Reverse mapping: Persian letter → Latin key for ISIRI 2901.
    public static let persianToKey: [Character: Character] = {
        var reverse: [Character: Character] = [:]
        for (latin, persian) in keyToPersian {
            reverse[persian] = latin
        }
        return reverse
    }()

    /// Converts a Persian string into the Latin keystroke sequence that produces it on ISIRI 2901.
    public static func convertToLatin(_ persian: String) -> String? {
        guard !persian.isEmpty else { return nil }
        var result = ""
        result.reserveCapacity(persian.count)
        for ch in persian {
            guard let latin = persianToKey[ch] else { return nil }
            result.append(latin)
        }
        return result
    }
    public static let persianLetters: Set<Character> = Set(keyToPersian.values).union(shiftKeyToPersian.values)

    /// Checks if a character is within the Unicode Arabic/Persian blocks or ZWNJ.
    public static func isPersianUnicode(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        return (value >= 0x0600 && value <= 0x06FF) ||
               (value >= 0xFB50 && value <= 0xFDFF) ||
               (value >= 0xFE70 && value <= 0xFEFF) ||
               value == 0x200C
    }

    /// The Persian letter produced by a physical key, if any.
    public static func persianLetter(for key: Character) -> Character? {
        if let shifted = shiftKeyToPersian[key] { return shifted }
        if let direct = keyToPersian[key] { return direct }
        if let lowered = key.lowercased().first, let fromLower = keyToPersian[lowered] {
            return fromLower
        }
        if persianLetters.contains(key) || isPersianUnicode(key) {
            return key
        }
        return nil
    }

    /// Converts a Latin keystroke sequence into its Persian equivalent.
    ///
    /// Returns `nil` when the sequence contains a character that has no
    /// Persian counterpart (digits, `/`, `@`, `.`, …), which means the token
    /// cannot be a Persian word at all.
    public static func convert(_ latin: String) -> String? {
        guard !latin.isEmpty else { return nil }
        var result = ""
        result.reserveCapacity(latin.count)
        for scalar in latin.unicodeScalars {
            if scalar.value == 0x200C {
                result.append("\u{200C}")
                continue
            }
            let character = Character(scalar)
            guard let letter = persianLetter(for: character) else { return nil }
            result.append(letter)
        }
        return result
    }

    /// Converts a single key, returning `nil` when the key has no Persian form.
    public static func convert(_ key: Character) -> Character? {
        persianLetter(for: key)
    }

    /// `true` when the token contains a Persian-only key at a position other
    /// than the final character. A trailing `,` is far more likely to be
    /// sentence punctuation than the Persian letter `و`.
    public static func containsInteriorPersianOnlyKey(_ token: String) -> Bool {
        guard token.count > 1 else { return false }
        for (index, character) in token.enumerated() {
            if index == token.count - 1 { continue }
            if persianOnlyKeys.contains(character) { return true }
        }
        return false
    }
}
