@testable import ShortcutKit
import Testing

@Suite("FuzzyFilter") struct FuzzyFilterTests {
    @Test("empty query matches everything with score 0")
    func emptyQuery() {
        #expect(FuzzyFilter.match(query: "", in: "Save")?.score == 0)
    }

    @Test("contiguous match beats non-contiguous match for same length")
    func contiguousBeatsScattered() {
        let cont = FuzzyFilter.match(query: "sav", in: "Save File")!
        let scat = FuzzyFilter.match(query: "sav", in: "Search Above Vault")!
        #expect(cont.score > scat.score)
    }

    @Test("start-of-word matches outscore mid-word matches")
    func startOfWordBeatsMidWord() {
        let start = FuzzyFilter.match(query: "p", in: "Print")!
        let mid = FuzzyFilter.match(query: "p", in: "Compile")!
        #expect(start.score > mid.score)
    }

    @Test("returns nil when not all query chars are present in order")
    func missesReturnNil() {
        #expect(FuzzyFilter.match(query: "xyz", in: "Save") == nil)
        #expect(FuzzyFilter.match(query: "evas", in: "Save") == nil)
    }

    @Test("case-insensitive")
    func caseInsensitive() {
        #expect(FuzzyFilter.match(query: "SAVE", in: "save file") != nil)
        #expect(FuzzyFilter.match(query: "save", in: "SAVE FILE") != nil)
    }
}
