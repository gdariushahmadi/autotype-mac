import Testing
@testable import AutoTypeCore

@Suite("Persian keyboard layout")
struct PersianLayoutTests {

    @Test("The home row matches the system Persian layout")
    func homeRow() {
        #expect(PersianLayout.convert("sghl") == "سلام")
        #expect(PersianLayout.convert("asdfghjkl") == "شسیبلاتنم")
    }

    @Test("The top row matches the system Persian layout")
    func topRow() {
        #expect(PersianLayout.convert("qwertyuiop") == "ضصثقفغعهخح")
    }

    @Test("The bottom row matches the system Persian layout")
    func bottomRow() {
        #expect(PersianLayout.convert("zxcvbnm,") == "ظطزرذدپو")
    }

    @Test("The punctuation keys that carry Persian letters")
    func persianOnlyKeys() {
        #expect(PersianLayout.persianOnlyKeys == ["[", "]", ";", "'", ","])
        #expect(PersianLayout.convert("[") == "ج")
        #expect(PersianLayout.convert("]") == "چ")
        #expect(PersianLayout.convert(";") == "ک")
        #expect(PersianLayout.convert("'") == "گ")
        #expect(PersianLayout.convert(",") == "و")
    }

    @Test("Characters with no Persian form")
    func unmappableCharacters() {
        #expect(PersianLayout.convert("hello1") == nil)
        #expect(PersianLayout.convert("a.b") == nil)
        #expect(PersianLayout.convert("a b") == nil)
    }

    @Test("Uppercase uses the same key")
    func uppercase() {
        #expect(PersianLayout.convert("SGH") == "سلا")
    }

    @Test("An interior Persian-only key is evidence, a trailing one is not")
    func interiorDetection() {
        #expect(PersianLayout.containsInteriorPersianOnlyKey("o,f"))
        #expect(!PersianLayout.containsInteriorPersianOnlyKey("hello,"))
        #expect(!PersianLayout.containsInteriorPersianOnlyKey("hello"))
    }

    @Test("Persian text is turned back into the Latin keys that produce it")
    func latinize() {
        #expect(PersianLayout.latinize("سلام") == "sghl")
        #expect(PersianLayout.latinize("کتاب") == ";jhf")
        #expect(PersianLayout.latinize("می‌رود") == "ld v,n")
    }

    @Test("Latinizing keeps everything that is not a Persian letter")
    func latinizeKeepsTheRest() {
        #expect(PersianLayout.latinize("سلام دنیا") == "sghl nkdh")
        #expect(PersianLayout.latinize("سلام، خوب!") == "sghl، o,f!")
        #expect(PersianLayout.latinize("hello 123") == "hello 123")
        #expect(PersianLayout.latinize("") == "")
    }
}
