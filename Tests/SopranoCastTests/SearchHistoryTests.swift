import AppKit
import Testing
@testable import SopranoCastCore

struct SearchHistoryTests {
    @Test("recording keeps entries newest first, unique and trimmed, ignoring blanks")
    func record() {
        var history = SearchHistory()
        history.record("chrome")
        history.record("  notes ")
        history.record("chrome")
        history.record("   ")
        history.record("")
        #expect(history.entries == ["chrome", "notes"])
    }

    @Test("at most 50 entries are kept, dropping the oldest")
    func limit() {
        var history = SearchHistory()
        for index in 0..<55 {
            history.record("query \(index)")
        }
        #expect(history.entries.count == 50)
        #expect(history.entries.first == "query 54")
        #expect(history.entries.last == "query 5")
    }

    @Test("previous walks older entries and returns nil past the oldest")
    func previousWalk() {
        var history = SearchHistory(entries: ["c", "b", "a"])
        #expect(history.previous(currentQuery: "") == "c")
        #expect(history.previous(currentQuery: "c") == "b")
        #expect(history.previous(currentQuery: "b") == "a")
        #expect(history.previous(currentQuery: "a") == nil)
        #expect(history.next() == "b")
    }

    @Test("previous from typing skips the newest entry when it equals the current query")
    func previousSkipsCurrent() {
        var history = SearchHistory(entries: ["chrome", "notes"])
        #expect(history.previous(currentQuery: " chrome ") == "notes")
        #expect(history.next() == nil)

        var other = SearchHistory(entries: ["chrome", "notes"])
        #expect(other.previous(currentQuery: "notes") == "chrome")
    }

    @Test("next walks newer entries and returns nil when back to typing")
    func nextWalk() {
        var history = SearchHistory(entries: ["c", "b", "a"])
        #expect(history.next() == nil)
        _ = history.previous(currentQuery: "")
        _ = history.previous(currentQuery: "c")
        #expect(history.next() == "c")
        #expect(history.next() == nil)
        #expect(history.next() == nil)
        #expect(history.previous(currentQuery: "typed") == "c")
    }

    @Test("resetting or recording returns to typing")
    func reset() {
        var history = SearchHistory(entries: ["c", "b", "a"])
        _ = history.previous(currentQuery: "")
        _ = history.previous(currentQuery: "c")
        history.resetCursor()
        #expect(history.next() == nil)
        #expect(history.previous(currentQuery: "") == "c")
        history.record("d")
        #expect(history.previous(currentQuery: "") == "d")
    }

    @Test("an empty history or one holding only the current query has nothing to show")
    func nothingToShow() {
        var empty = SearchHistory()
        #expect(empty.previous(currentQuery: "") == nil)
        var single = SearchHistory(entries: ["chrome"])
        #expect(single.previous(currentQuery: "chrome") == nil)
        #expect(single.next() == nil)
    }
}
