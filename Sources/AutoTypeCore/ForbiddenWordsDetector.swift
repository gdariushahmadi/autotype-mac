import Foundation

/// Fast detector for forbidden or sensitive words in sentences.
/// Used to intercept accidental Enter presses when text contains prohibited words or phrases.
public enum ForbiddenWordsDetector {

    /// Punctuation and symbol characters used to split words.
    private static let tokenSeparators: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(CharacterSet.punctuationCharacters)
        set.formUnion(CharacterSet.symbols)
        set.insert(charactersIn: "«»؛،؟…ـ\"'`()[]{}<>:;,?!/\\|@#$%^&*+=~")
        return set
    }()

    /// Detects forbidden words or phrases within the given text.
    /// Supports Persian and English, case-insensitivity, ZWNJ variations, clitics, and QWERTY layouts.
    public static func findMatches(in text: String, forbiddenWords: [String]) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !forbiddenWords.isEmpty else { return [] }

        // Clean and prepare the list of forbidden entries
        let activeForbidden = forbiddenWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !activeForbidden.isEmpty else { return [] }

        // Normalized text for phrase comparisons (without ZWNJ and Arabic letter variants)
        let normalizedText = PersianText.lookupKey(trimmedText).lowercased()

        // Extract individual tokens from text
        let rawTokens = trimmedText.components(separatedBy: tokenSeparators)
            .map { $0.trimmingCharacters(in: tokenSeparators) }
            .filter { !$0.isEmpty }

        let normalizedTokens = rawTokens.map { PersianText.lookupKey($0).lowercased() }

        var matches: [String] = []

        for forbidden in activeForbidden {
            let normalizedForbidden = PersianText.lookupKey(forbidden).lowercased()
            guard !normalizedForbidden.isEmpty else { continue }

            // 1. Multi-word phrase check (contains space or tab or ZWNJ)
            if forbidden.contains(" ") || forbidden.contains("\t") || forbidden.contains(PersianText.zeroWidthNonJoiner) {
                if normalizedText.contains(normalizedForbidden) {
                    if !matches.contains(forbidden) {
                        matches.append(forbidden)
                    }
                    continue
                }
            }

            // 2. Exact token match or clitic match
            var found = false
            for token in normalizedTokens {
                if token == normalizedForbidden {
                    found = true
                    break
                }

                // Check Persian clitic suffix (e.g. "کتاب‌ها" -> "کتاب")
                if let (stem, _) = PersianText.splitCliticSuffix(token) {
                    let normStem = PersianText.lookupKey(stem).lowercased()
                    if normStem == normalizedForbidden {
                        found = true
                        break
                    }
                }

                // Check common plural / pronoun suffixes without ZWNJ (e.g. "ها", "های")
                for suffix in ["ها", "های", "مان", "تان", "شان", "ت", "م", "ش"] {
                    if token.count > suffix.count + 1 && token.hasSuffix(suffix) {
                        let stem = String(token.dropLast(suffix.count))
                        if stem == normalizedForbidden {
                            found = true
                            break
                        }
                    }
                }

                // Check if typed with QWERTY keyboard layout without conversion
                if let converted = PersianLayout.convert(token) {
                    let normConverted = PersianText.lookupKey(converted).lowercased()
                    if normConverted == normalizedForbidden {
                        found = true
                        break
                    }
                }
            }

            if found {
                if !matches.contains(forbidden) {
                    matches.append(forbidden)
                }
            }
        }

        return matches
    }
}
