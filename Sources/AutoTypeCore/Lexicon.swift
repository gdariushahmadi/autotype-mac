import Foundation

/// A word list kept on disk and searched in place.
///
/// The list is sorted, so a lookup is a binary search over the raw bytes —
/// no `String` is allocated for words that are never queried. That keeps a
/// 400 000-word Persian lexicon at a few megabytes of resident memory and
/// makes start-up instant.
public final class SortedWordList {

    private let bytes: [UInt8]
    private let lineStarts: [Int]
    private let lineEnds: [Int]
    private let hasTab: Bool

    /// An empty list, used when the dictionary files cannot be read.
    public init() {
        bytes = []
        lineStarts = []
        lineEnds = []
        hasTab = false
    }

    /// - Parameter keyTerminator: byte that ends the lookup key. When `nil`
    ///   the whole line is the key.
    public init(contentsOf url: URL, keyTerminator: UInt8?) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        bytes = [UInt8](data)

        var starts: [Int] = []
        var ends: [Int] = []
        starts.reserveCapacity(bytes.count / 8)
        ends.reserveCapacity(bytes.count / 8)

        var lineStart = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0A {  // \n
                ends.append(index)
                starts.append(lineStart)
                lineStart = index + 1
            }
            index += 1
        }
        if lineStart < bytes.count {
            ends.append(bytes.count)
            starts.append(lineStart)
        }
        lineStarts = starts
        lineEnds = ends
        hasTab = keyTerminator != nil
        _ = keyTerminator
    }

    public var count: Int { lineStarts.count }

    /// Returns the raw bytes of the line at `index`, without the line ending.
    public func line(at index: Int) -> ArraySlice<UInt8> {
        bytes[lineStarts[index]..<lineEnds[index]]
    }

    /// The lookup key of a line: everything before the first tab.
    private func keyRange(at index: Int) -> Range<Int> {
        let lower = lineStarts[index]
        let upper = lineEnds[index]
        guard hasTab else { return lower..<upper }
        var cursor = lower
        while cursor < upper, bytes[cursor] != 0x09 { cursor += 1 }
        return lower..<cursor
    }

    /// Binary search for `key`. Returns the line index or `nil`.
    public func index(of key: [UInt8]) -> Int? {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = keyRange(at: mid)
            let comparison = Self.compare(bytes[range], key)
            if comparison == 0 { return mid }
            if comparison < 0 { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    /// `true` when the list contains `word`.
    public func contains(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        return index(of: Array(word.utf8)) != nil
    }

    /// Checks for a word that starts with the supplied key.
    public func containsPrefix(_ prefix: String) -> Bool {
        let key = Array(prefix.utf8)
        guard !key.isEmpty else { return false }
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if Self.compare(bytes[keyRange(at: mid)], key) < 0 {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < lineStarts.count else { return false }
        return bytes[keyRange(at: low)].starts(with: key)
    }

    /// Lexicographic comparison of two byte ranges.
    private static func compare(_ lhs: ArraySlice<UInt8>, _ rhs: [UInt8]) -> Int {
        var left = lhs.startIndex
        let leftEnd = lhs.endIndex
        var right = 0
        while left < leftEnd, right < rhs.count {
            let a = lhs[left]
            let b = rhs[right]
            if a != b { return a < b ? -1 : 1 }
            left += 1
            right += 1
        }
        if left < leftEnd { return 1 }
        if right < rhs.count { return -1 }
        return 0
    }

    /// All lines, decoded as strings. Used by the dictionary editor UI.
    public func allLines() -> [String] {
        (0..<lineStarts.count).map { index in
            String(decoding: line(at: index), as: UTF8.self)
        }
    }
}

/// A Persian dictionary entry.
public struct PersianEntry: Equatable {
    /// The canonical spelling, including any ZWNJ the language requires.
    public let canonical: String
    /// `true` when the word is among the most frequent Persian words.
    public let isCommon: Bool
}

/// The word lists AutoType uses to decide whether a token is Persian.
public final class Lexicon {

    private let persianList: SortedWordList
    private let englishList: SortedWordList
    private let englishCommonList: SortedWordList

    /// Persian words the user explicitly added. They always win.
    public var personalPersian: Set<String> = []
    /// Words the user explicitly protected. They are never converted.
    public var protectedEnglish: Set<String> = []

    public init(persianURL: URL, englishURL: URL, englishCommonURL: URL) throws {
        persianList = try SortedWordList(contentsOf: persianURL, keyTerminator: 0x09)
        englishList = try SortedWordList(contentsOf: englishURL, keyTerminator: nil)
        englishCommonList = try SortedWordList(contentsOf: englishCommonURL, keyTerminator: nil)
    }

    /// A lexicon that knows nothing, used as a fallback when the dictionary
    /// files cannot be read.
    public static func empty() -> Lexicon {
        Lexicon(persian: SortedWordList(), english: SortedWordList(), englishCommon: SortedWordList())
    }

    private init(persian: SortedWordList, english: SortedWordList, englishCommon: SortedWordList) {
        persianList = persian
        englishList = english
        englishCommonList = englishCommon
    }

    // MARK: - Persian

    /// The number of Persian words in the dictionary.
    public var persianCount: Int { persianList.count }

    /// The number of English words in the dictionary.
    public var englishCount: Int { englishList.count }

    /// Looks a Persian word up. `word` may use any Persian orthography; the
    /// lookup ignores ZWNJ and folds Arabic yeh/kaf onto their Persian forms.
    public func persianEntry(for word: String) -> PersianEntry? {
        let key = PersianText.lookupKey(word)
        guard !key.isEmpty else { return nil }
        if personalPersian.contains(key) {
            return PersianEntry(canonical: word, isCommon: true)
        }
        guard let index = persianList.index(of: Array(key.utf8)) else { return nil }
        let line = persianList.line(at: index)
        let fields = Self.split(line, by: 0x09)
        let canonical = fields.count > 1 && !fields[1].isEmpty ? fields[1] : key
        let isCommon = fields.count > 2 && fields[2] == "1"
        return PersianEntry(canonical: canonical, isCommon: isCommon)
    }

    public func containsPersian(_ word: String) -> Bool {
        persianEntry(for: word) != nil
    }

    public func containsPersianPrefix(_ prefix: String) -> Bool {
        let key = PersianText.lookupKey(prefix)
        guard !key.isEmpty else { return false }
        return persianList.containsPrefix(key) || personalPersian.contains { PersianText.lookupKey($0).hasPrefix(key) }
    }

    // MARK: - English

    /// `true` when the token is a known English word.
    public func containsEnglish(_ word: String) -> Bool {
        let key = word.lowercased()
        guard !key.isEmpty else { return false }
        if protectedEnglish.contains(key) { return true }
        // In the English language, only "a" and "i" can be standalone words.
        // Isolated letters (e.g. b, c, d, h, f, n, l, s) are not English words.
        if key.count == 1 && key != "a" && key != "i" {
            return false
        }
        return englishList.contains(key)
    }

    public func containsEnglishPrefix(_ prefix: String) -> Bool {
        let key = prefix.lowercased()
        guard !key.isEmpty else { return false }
        return englishList.containsPrefix(key) || protectedEnglish.contains { $0.lowercased().hasPrefix(key) }
    }

    /// `true` when the token is a frequently used English word.
    public func isCommonEnglish(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.count == 1 && lower != "a" && lower != "i" {
            return false
        }
        return englishCommonList.contains(lower)
    }

    /// Every English word in the list — used by the dictionary editor.
    public var allEnglishWords: [String] {
        englishList.allLines()
    }

    // MARK: - Helpers

    private static func split(_ line: ArraySlice<UInt8>, by separator: UInt8) -> [String] {
        var fields: [String] = []
        var current: [UInt8] = []
        for byte in line {
            if byte == separator {
                fields.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        fields.append(String(decoding: current, as: UTF8.self))
        return fields
    }
}
