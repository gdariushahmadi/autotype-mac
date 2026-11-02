import Foundation

/// Detects strings that must survive untouched.
///
/// Emails, URLs, IP addresses, file paths, version numbers, code identifiers
/// and numbers all look like ordinary Latin words to a naive converter, but
/// rewriting them corrupts the text. These are recognised *before* any
/// language scoring happens.
public enum TechnicalPatterns {

    /// Characters that can never appear in a Persian word.
    private static let nonWordCharacters = Set("0123456789@#$%&*+=~^/\\|<>\"`_ ")

    /// `true` when the token contains a character that has no Persian
    /// counterpart, so it cannot be a Persian word at all.
    public static func containsNonPersianCharacter(_ token: String) -> Bool {
        token.contains { nonWordCharacters.contains($0) }
    }

    /// `true` when the token is a technical string that must be preserved.
    public static func isTechnical(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        if token.contains("\u{200C}") { return false }
        if containsNonPersianCharacter(token) { return true }
        if isURL(token) { return true }
        if isEmail(token) { return true }
        if isIPAddress(token) { return true }
        if isFilePath(token) { return true }
        if isVersionNumber(token) { return true }
        if isCodeIdentifier(token) { return true }
        if isAcronym(token) { return true }
        if isHexColor(token) { return true }
        if isClockTime(token) { return true }
        return false
    }

    // MARK: - Individual patterns

    public static func isURL(_ token: String) -> Bool {
        let lower = token.lowercased()
        if lower.contains("://") { return true }
        if lower.hasPrefix("www.") { return true }
        if lower.hasPrefix("mailto:") { return true }
        // host.tld/path, where the last label looks like a top level domain.
        guard let dot = token.lastIndex(of: ".") else { return false }
        let tld = token[token.index(after: dot)...]
        guard !tld.isEmpty, tld.count <= 6 else { return false }
        guard tld.allSatisfy({ $0.isLetter }) else { return false }
        let host = token[..<dot]
        guard !host.isEmpty else { return false }
        return host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
    }

    public static func isEmail(_ token: String) -> Bool {
        guard let at = token.firstIndex(of: "@"), at != token.startIndex else { return false }
        let domain = token[token.index(after: at)...]
        guard domain.contains("."), !domain.hasSuffix(".") else { return false }
        let local = token[..<at]
        return !local.isEmpty && !local.contains(" ")
    }

    public static func isIPAddress(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), part.count <= 3,
                  let value = Int(part), value <= 255 else { return false }
        }
        return true
    }

    public static func isFilePath(_ token: String) -> Bool {
        if token.hasPrefix("/") || token.hasPrefix("./") || token.hasPrefix("../") || token.hasPrefix("~/") {
            return true
        }
        if token.contains("\\") { return true }
        // Windows drive letter, e.g. C:\Users
        if token.count > 2, token.first!.isLetter, token[token.index(token.startIndex, offsetBy: 1)] == ":" {
            return true
        }
        return false
    }

    public static func isVersionNumber(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return false }
        var digits = 0
        for part in parts {
            guard !part.isEmpty else { return false }
            for character in part {
                guard character.isNumber else { return false }
            }
            digits += part.count
        }
        return digits >= 3
    }

    /// `snake_case`, `camelCase`, `PascalCase`, `kebab-case` and `func()`.
    public static func isCodeIdentifier(_ token: String) -> Bool {
        if token.contains("_") { return true }
        if token.contains("()") { return true }
        if token.hasSuffix("()") { return true }
        if isKebabCase(token) { return true }
        // Code identifiers in programming languages never contain Persian punctuation keys (comma, semicolon, brackets, apostrophe)
        if token.contains(where: { PersianLayout.persianOnlyKeys.contains($0) }) {
            return false
        }
        // camelCase / PascalCase: an uppercase letter after the first character.
        if token.count > 1 {
            let characters = Array(token)
            for index in 1..<characters.count where characters[index].isUppercase {
                if characters[index - 1].isLowercase { return true }
            }
        }
        return false
    }

    /// `true` when the token matches an unambiguous technical pattern
    /// (URL, email, IP address, file path, version number, hex color, clock time, underscore, or explicit non-word character).
    public static func isHardTechnical(_ token: String) -> Bool {
        if containsNonPersianCharacter(token) { return true }
        if isURL(token) { return true }
        if isEmail(token) { return true }
        if isIPAddress(token) { return true }
        if isFilePath(token) { return true }
        if isVersionNumber(token) { return true }
        if isHexColor(token) { return true }
        if isClockTime(token) { return true }
        if token.contains("_") || token.contains("()") || token.hasSuffix("()") { return true }
        return false
    }

    /// `true` when the token is a kebab-case identifier, slug or CLI flag (e.g. `shakiba-academy-beauty`, `my-app`, `--flag`).
    public static func isKebabCase(_ token: String) -> Bool {
        guard token.contains("-") else { return false }
        guard !token.contains("\u{200C}") else { return false }
        if token.hasPrefix("-") && token.count >= 2 { return true }
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
    }

    public static func isAcronym(_ token: String) -> Bool {
        guard !token.contains("\u{200C}") else { return false }
        guard token.count >= 2 else { return false }
        let letters = token.filter { $0.isLetter }
        guard letters.count == token.count, letters.count >= 2 else { return false }
        return letters.allSatisfy { $0.isUppercase }
    }

    public static func isHexColor(_ token: String) -> Bool {
        guard token.hasPrefix("#") else { return false }
        let digits = token.dropFirst()
        guard digits.count == 3 || digits.count == 6 else { return false }
        return digits.allSatisfy { $0.isHexDigit }
    }

    public static func isClockTime(_ token: String) -> Bool {
        let parts = token.split(separator: ":")
        guard (2...3).contains(parts.count) else { return false }
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), part.count <= 2 else { return false }
        }
        return true
    }

    /// Contractions that are not always present in a system dictionary.
    public static let contractions: Set<String> = [
        "don't", "doesn't", "didn't", "can't", "cannot", "won't", "wouldn't", "shan't",
        "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't",
        "shouldn't", "couldn't", "mustn't", "ain't", "i'm", "i've", "i'll", "i'd",
        "you're", "you've", "you'll", "you'd", "we're", "we've", "we'll", "we'd",
        "they're", "they've", "they'll", "they'd", "it's", "that's", "there's",
        "here's", "what's", "who's", "let's", "gonna", "wanna", "gotta", "dunno",
        "y'all", "ma'am", "o'clock", "'tis", "'twas", "e'er", "ne'er", "o'er",
    ]

    /// `true` when the token is a known English contraction.
    public static func isContraction(_ token: String) -> Bool {
        contractions.contains(token.lowercased())
    }
}
