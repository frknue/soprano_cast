import Foundation

/// Root Search's query history, browsed with ↑/↓ when the selection sits at the edge of
/// the list (Raycast's "search history").
public struct SearchHistory: Equatable, Sendable {
    /// How many queries are kept.
    public static let maxEntries = 50

    /// Newest first, unique, at most `maxEntries`.
    public private(set) var entries: [String]
    /// The entry being shown while browsing; nil while typing.
    private var cursor: Int?
    /// Where browsing started; going newer past it returns to typing.
    private var start = 0

    public init(entries: [String] = []) {
        var seen = Set<String>()
        self.entries = Array(entries.filter { seen.insert($0).inserted }.prefix(SearchHistory.maxEntries))
    }

    /// Moves the query (trimmed) to the front; ignores empty / whitespace. Resets browsing.
    public mutating func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        if entries.count > SearchHistory.maxEntries {
            entries.removeLast(entries.count - SearchHistory.maxEntries)
        }
        resetCursor()
    }

    /// ↑ at the top of the list: the next older entry (nil past the end, staying on the
    /// oldest). From typing it starts at the newest entry that differs from `currentQuery`
    /// (trimmed).
    public mutating func previous(currentQuery: String) -> String? {
        if let cursor {
            guard cursor + 1 < entries.count else { return nil }
            self.cursor = cursor + 1
            return entries[cursor + 1]
        }
        let current = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = entries.firstIndex(where: { $0 != current }) else { return nil }
        start = first
        cursor = first
        return entries[first]
    }

    /// ↓: the next newer entry; nil when browsing goes back to typing (or wasn't browsing).
    public mutating func next() -> String? {
        guard let cursor else { return nil }
        guard cursor > start else {
            resetCursor()
            return nil
        }
        self.cursor = cursor - 1
        return entries[cursor - 1]
    }

    /// Back to typing (the query was edited, or the launcher closed).
    public mutating func resetCursor() {
        cursor = nil
        start = 0
    }
}
