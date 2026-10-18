import AppKit
import Testing
@testable import SopranoCastCore

struct SearchMatcherTests {
    private func score(_ query: String, _ text: String) -> Int? {
        SearchMatcher.match(query, in: text)?.score
    }

    private func highlighted(_ query: String, _ text: String) -> [String]? {
        SearchMatcher.match(query, in: text)?.ranges.map { String(text[$0]) }
    }

    @Test("an empty or blank query matches everything with score 0 and no ranges")
    func emptyQuery() {
        #expect(SearchMatcher.match("", in: "Safari") == SearchMatch(score: 0, ranges: []))
        #expect(SearchMatcher.match("  \t ", in: "") == SearchMatch(score: 0, ranges: []))
    }

    @Test("characters must appear in order")
    func subsequence() {
        #expect(SearchMatcher.match("xyz", in: "Safari") == nil)
        #expect(SearchMatcher.match("ifs", in: "Safari") == nil)
        #expect(SearchMatcher.match("sfi", in: "Safari") != nil)
        #expect(SearchMatcher.match("a", in: "") == nil)
    }

    @Test("every whitespace-separated term must match, each anywhere")
    func multipleTerms() {
        #expect(SearchMatcher.match("chrome google", in: "Google Chrome") != nil)
        #expect(SearchMatcher.match("google zzz", in: "Google Chrome") == nil)
        #expect(highlighted("chr goo", "Google Chrome") == ["Goo", "Chr"])
    }

    @Test("matching ignores case and diacritics on both sides")
    func caseAndDiacritics() {
        #expect(highlighted("CAFE", "café crème") == ["café"])
        #expect(highlighted("creme", "Café Crème") == ["Crème"])
        #expect(highlighted("crème", "creme brulee") == ["creme"])
    }

    @Test("ranges point at the original text's characters")
    func rangesUseOriginalIndices() {
        let text = "🎵 Música Player"
        let match = SearchMatcher.match("mus", in: text)
        #expect(match?.ranges.count == 1)
        if let range = match?.ranges.first {
            #expect(text[range] == "Mús")
            #expect(text.distance(from: text.startIndex, to: range.lowerBound) == 2)
        }
        #expect(highlighted("sfi", "Safari") == ["S", "f", "i"])
    }

    @Test("word starts and consecutive characters score higher")
    func bonuses() {
        #expect(score("saf", "Safari")! > score("saf", "Mesa Fish")!)
        #expect(score("gh", "GitHub")! > score("gh", "bigshot hat")!)
        #expect(score("ari", "zzari")! > score("ari", "zazrzi")!)
    }

    @Test("the best placement is used when a term matches in several places")
    func bestPlacement() {
        #expect(highlighted("ter", "Twitter Terminal") == ["Ter"])
    }
}
