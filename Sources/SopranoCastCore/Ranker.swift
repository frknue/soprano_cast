import Foundation

/// Root Search: turns the query, the items and the user's settings and usage into sections.
public enum Ranker {
    public static let maxResults = 60
    /// Rows in the empty-query Suggestions section.
    public static let maxSuggestions = 6

    static let tierWeight = 1_000_000
    static let matchWeight = 1_000
    /// Match scores are capped so they never spill into the next tier.
    static let maxMatchScore = 999
    static let favoriteBonus = 50

    /// Root Search sections for `query` (trimmed). Empty query: `.favorites` (settings order,
    /// existing, not disabled) then `.suggestions` (top 6 by frecency, excluding favorites,
    /// only items used at least once). Otherwise: `.calculator` (when `calculator` is non-nil,
    /// one row: `ItemID.calculatorResult`, title = formatted answer, subtitle = expression),
    /// `.results`, `.fallbacks` (settings.fallbacks that exist and aren't disabled). Empty
    /// sections are omitted.
    ///
    /// Results: per non-disabled item, alias equal to the query → tier 3, alias starting
    /// with it → tier 2, else the best fuzzy match over the title (full weight), keywords
    /// and subtitle (half weight) → tier 1; no match → excluded. Score = tier × 1 000 000 +
    /// match score × 1 000 + frecency + 50 for favorites; ties by title
    /// (`localizedStandardCompare`), then id. At most `maxResults` rows.
    public static func sections(
        query: String, items: [CastItem], settings: CastSettings,
        usage: [ItemID: UsageRecord], now: Date, calculator: CalculatorResult?
    ) -> [ResultSection] {
        // Enabled items by id; the first item wins when an id repeats.
        var enabled: [ItemID: CastItem] = [:]
        var ordered: [CastItem] = []
        for item in items where !settings.disabled.contains(item.id) && enabled[item.id] == nil {
            enabled[item.id] = item
            ordered.append(item)
        }
        func frecency(_ id: ItemID) -> Int {
            usage[id].map { Frecency.score($0, now: now) } ?? 0
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections: [ResultSection]
        if trimmed.isEmpty {
            let favorites = unique(settings.favorites).compactMap { enabled[$0] }
            let favoriteIDs = Set(settings.favorites)
            let suggestions = ordered
                .filter { !favoriteIDs.contains($0.id) && !(usage[$0.id]?.uses.isEmpty ?? true) }
                .map { RankedItem(item: $0, score: frecency($0.id)) }
                .sorted(by: precedes)
            sections = [
                ResultSection(kind: .favorites, rows: favorites.map { RankedItem(item: $0, score: frecency($0.id)) }),
                ResultSection(kind: .suggestions, rows: Array(suggestions.prefix(maxSuggestions))),
            ]
        } else {
            let favoriteIDs = Set(settings.favorites)
            let results = ordered
                .compactMap { item in
                    ranked(item, query: trimmed, alias: settings.aliases[item.id], frecency: frecency(item.id),
                           isFavorite: favoriteIDs.contains(item.id))
                }
                .sorted(by: precedes)
            let fallbacks = unique(settings.fallbacks).compactMap { enabled[$0] }.map { RankedItem(item: $0, score: 0) }
            sections = [
                ResultSection(kind: .calculator, rows: calculator.map { [RankedItem(item: calculatorItem($0), score: 0)] } ?? []),
                ResultSection(kind: .results, rows: Array(results.prefix(maxResults))),
                ResultSection(kind: .fallbacks, rows: fallbacks),
            ]
        }
        return sections.filter { !$0.rows.isEmpty }
    }

    /// The calculator row: title = formatted answer, subtitle = expression.
    static func calculatorItem(_ result: CalculatorResult) -> CastItem {
        CastItem(id: .calculatorResult, title: result.formatted, subtitle: result.expression, icon: .glyph(.calculator))
    }

    /// One item ranked against a non-empty, trimmed query; nil when nothing matches.
    private static func ranked(_ item: CastItem, query: String, alias: String?, frecency: Int, isFavorite: Bool) -> RankedItem? {
        let titleMatch = SearchMatcher.match(query, in: item.title)
        var best = titleMatch?.score
        for text in item.keywords + [item.subtitle] {
            guard let match = SearchMatcher.match(query, in: text) else { continue }
            best = max(best ?? 0, match.score / 2)
        }
        let lowered = query.lowercased()
        let tier: Int
        if let alias, alias == lowered {
            tier = 3
        } else if let alias, alias.hasPrefix(lowered) {
            tier = 2
        } else if best != nil {
            tier = 1
        } else {
            return nil
        }
        let score = tier * tierWeight
            + min(best ?? 0, maxMatchScore) * matchWeight
            + frecency
            + (isFavorite ? favoriteBonus : 0)
        return RankedItem(item: item, score: score, titleRanges: titleMatch?.ranges ?? [], matchedAlias: tier >= 2)
    }

    /// Higher score first, then title (`localizedStandardCompare`), then id.
    private static func precedes(_ lhs: RankedItem, _ rhs: RankedItem) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        switch lhs.item.title.localizedStandardCompare(rhs.item.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.item.id < rhs.item.id
        }
    }

    /// `ids` without repeats, first occurrence kept.
    private static func unique(_ ids: [ItemID]) -> [ItemID] {
        var seen = Set<ItemID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
