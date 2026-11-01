import Foundation

/// Cheap structural checks that a Persian string could plausibly be a word.
///
/// This is the last line of defence for words that neither dictionary knows:
/// before converting something unknown, the shape of the result has to look
/// like Persian rather than like a mangled English word.
public enum PersianPhonotactics {

    /// Characters that can carry a vowel.
    private static let vowels: Set<Character> = ["ا", "و", "ی", "ئ", "ه", "آ", "أ", "إ", "ؤ", "ٔ"]

    /// Characters that can start a syllable.
    private static let consonants: Set<Character> = Set(PersianLayout.persianLetters).subtracting(vowels)

    /// The longest run of consonants Persian allows inside one syllable.
    private static let maximumConsonantRun = 3

    /// `true` when the string has the shape of a plausible Persian word.
    public static func looksPersian(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "\u{200C}", with: "")
        guard normalized.count >= 2 else { return false }
        var consonantRun = 0
        var hasVowel = false
        for character in normalized {
            if vowels.contains(character) {
                consonantRun = 0
                hasVowel = true
            } else if consonants.contains(character) {
                consonantRun += 1
                if consonantRun > maximumConsonantRun { return false }
            } else {
                return false
            }
        }
        return hasVowel
    }
}
