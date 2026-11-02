import Testing
@testable import AutoTypeCore

@Suite("Punctuation spacing")
struct PunctuationSpacingTests {
    @Test("Normalize spaces around punctuation without adding a trailing space")
    func punctuation() throws {
        let lexicon = try AutoTypeResources.loadLexicon()
        let input = "سلام .خوبی ؟بگو ،درسته ؛بله :ممنون !"
        #expect(PunctuationSpacing.normalize(input, lexicon: lexicon) == "سلام. خوبی؟ بگو، درسته؛ بله: ممنون!")
        #expect(PunctuationSpacing.normalize("سلام؟!خوبی", lexicon: lexicon) == "سلام؟! خوبی")
        #expect(PunctuationSpacing.normalize("سلام.\nخوبی", lexicon: lexicon) == "سلام.\nخوبی")
    }

    @Test("Keep technical tokens, numbers and Persian keyboard words intact")
    func protectedTokens() throws {
        let lexicon = try AutoTypeResources.loadLexicon()
        for input in ["3.14", "12:30", "test@example.com", "https://example.com/a?x=1", "/usr/local/bin", "o,f", "سلام(خوب)"] {
            #expect(PunctuationSpacing.normalize(input, lexicon: lexicon) == input)
        }
    }
}
