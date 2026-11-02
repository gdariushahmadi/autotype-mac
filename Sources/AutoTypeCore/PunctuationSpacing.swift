import Foundation

/// Normalizes spaces around sentence punctuation in text that has been typed.
public enum PunctuationSpacing {
    private static let marks: Set<Character> = [".", ",", "،", ";", "؛", ":", "?", "؟", "!"]

    public static func normalize(_ text: String, lexicon: Lexicon) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }
        var protected = Array(repeating: false, count: characters.count)
        var start = 0
        while start < characters.count {
            if characters[start].isWhitespace { start += 1; continue }
            var end = start
            while end < characters.count && !characters[end].isWhitespace { end += 1 }
            let token = String(characters[start..<end])
            let persianWord = PersianLayout.convert(token).map { lexicon.containsPersian($0) } ?? false
            let technical = token.contains(where: { $0.isNumber || "@/\\_#`".contains($0) }) ||
                TechnicalPatterns.isURL(token) || TechnicalPatterns.isFilePath(token) ||
                TechnicalPatterns.isKebabCase(token) || persianWord ||
                token.hasPrefix("-") || token.contains("(") || token.contains(")")
            if technical { for index in start..<end { protected[index] = true } }
            start = end
        }

        var result = ""
        for index in characters.indices {
            let character = characters[index]
            guard marks.contains(character), !protected[index] else {
                result.append(character)
                continue
            }
            let beforeSpaces = result.reversed().drop(while: { $0 == " " }).first
            if let beforeSpaces, !beforeSpaces.isWhitespace, !"([{«“.".contains(beforeSpaces) {
                while result.last == " " { result.removeLast() }
            }
            result.append(character)
            guard index + 1 < characters.count else { continue }
            let next = characters[index + 1]
            if !next.isWhitespace && !marks.contains(next) && !")]}»”".contains(next) &&
                !protected[index + 1] && (next.isLetter || next.isNumber) {
                result.append(" ")
            }
        }
        return result
    }
}
