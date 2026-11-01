import Foundation

/// Fast functional typo and spelling irregularity detector for Persian text.
public enum TypoDetector {

    /// Common Persian typo substitutions where visually or phonetically similar keys are swapped
    public static let commonTypoMap: [String: String] = [
        "پروژع": "پروژه",
        "موفغیت": "موفقیت",
        "انجلم": "انجام",
        "نامع": "نامه",
        "خاهش": "خواهش",
        "خاهر": "خواهر",
        "حتا": "حتی",
        "اتفاقن": "اتفاقاً",
        "لطفن": "لطفاً",
        "فعلن": "فعلاً",
        "اصلن": "اصلاً",
        "حتمن": "حتماً",
        "راجب": "راجع به",
        "خاستن": "خواستن"
    ]

    public struct AnalysisResult: Sendable, Equatable {
        public let hasSuspiciousTokens: Bool
        public let suspiciousTokens: [String]
        public let suggestions: [String: String]

        public init(hasSuspiciousTokens: Bool, suspiciousTokens: [String], suggestions: [String: String]) {
            self.hasSuspiciousTokens = hasSuspiciousTokens
            self.suspiciousTokens = suspiciousTokens
            self.suggestions = suggestions
        }
    }

    /// Analyzes a line of Persian text and detects potential typos, impossible consonant runs,
    /// or broken words that should intercept accidental Enter sends.
    public static func analyze(_ text: String) -> AnalysisResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AnalysisResult(hasSuspiciousTokens: false, suspiciousTokens: [], suggestions: [:])
        }

        // Split into tokens (dropping punctuation)
        let rawTokens = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:()[]{}«»؟،؛\"'")) }
            .filter { !$0.isEmpty }

        var suspicious: [String] = []
        var suggestions: [String: String] = [:]

        for token in rawTokens {
            // Skip technical tokens, URLs, English words, numbers
            if TechnicalPatterns.isTechnical(token) || token.allSatisfy({ $0.isASCII }) {
                continue
            }

            // Check dictionary typo mappings
            if let correction = commonTypoMap[token] {
                suspicious.append(token)
                suggestions[token] = correction
                continue
            }

            // Check for illegal trailing ayn where heh is expected (e.g. *ع at end of 4+ letter word)
            if token.count >= 4 && token.hasSuffix("ع") {
                let candidate = String(token.dropLast()) + "ه"
                suspicious.append(token)
                suggestions[token] = candidate
                continue
            }

            // Check for impossible consonant clusters in Persian
            if PersianText.containsPersian(token) && !PersianPhonotactics.looksPersian(token) {
                // If it's not a known single letter
                if token.count >= 3 {
                    suspicious.append(token)
                }
            }
        }

        return AnalysisResult(
            hasSuspiciousTokens: !suspicious.isEmpty,
            suspiciousTokens: suspicious,
            suggestions: suggestions
        )
    }
}
