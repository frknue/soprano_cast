import AppKit
import Testing
@testable import SopranoCastCore

struct RankerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let searchGoogle = ItemID(kind: .castCommand, key: CastCommand.searchGoogle.rawValue)

    private func app(_ key: String, _ title: String, subtitle: String = "", keywords: [String] = []) -> CastItem {
        CastItem(id: ItemID(kind: .application, key: key), title: title, subtitle: subtitle, keywords: keywords,
                 icon: .file(path: "/Applications/\(title).app"))
    }

    private func used(_ times: Int) -> UsageRecord {
        UsageRecord(uses: Array(repeating: now.addingTimeInterval(-3_600), count: times))
    }

    private func sections(
        _ query: String, _ items: [CastItem], settings: CastSettings = CastSettings(),
        usage: [ItemID: UsageRecord] = [:], calculator: CalculatorResult? = nil
    ) -> [ResultSection] {
        Ranker.sections(query: query, items: items, settings: settings, usage: usage, now: now, calculator: calculator)
    }

    private func titles(_ sections: [ResultSection], _ kind: SectionKind) -> [String] {
        sections.first { $0.kind == kind }?.rows.map { $0.item.title } ?? []
    }

    // MARK: Query tiers

    @Test("an exact alias beats a better fuzzy title match")
    func aliasExact() {
        let chrome = app("com.google.Chrome", "Google Chrome")
        let tool = app("gc", "GC")
        var settings = CastSettings()
        settings.aliases = [chrome.id: "gc"]
        let result = sections("GC", [tool, chrome], settings: settings)
        #expect(titles(result, .results) == ["Google Chrome", "GC"])
        let row = result.first { $0.kind == .results }?.rows.first
        #expect(row?.matchedAlias == true)
        #expect(row.map { $0.score >= 3_000_000 } == true)
    }

    @Test("an alias starting with the query ranks between exact aliases and fuzzy matches")
    func aliasPrefix() {
        let chrome = app("com.google.Chrome", "Google Chrome")
        let calendar = app("com.apple.iCal", "Calendar")
        let chess = app("com.apple.Chess", "Chess")
        var settings = CastSettings()
        settings.aliases = [chrome.id: "chr", calendar.id: "ch"]
        let result = sections("ch", [chess, chrome, calendar], settings: settings)
        #expect(titles(result, .results) == ["Calendar", "Google Chrome", "Chess"])
        let rows = result.first { $0.kind == .results }?.rows ?? []
        #expect(rows.map { $0.matchedAlias } == [true, true, false])
        #expect(rows.map { $0.score / 1_000_000 } == [3, 2, 1])
    }

    @Test("keywords and subtitles match at half the weight of the title")
    func halfWeight() {
        let terminal = app("com.apple.Terminal", "Terminal")
        let byKeyword = app("dev.warp", "Warp", keywords: ["terminal"])
        let bySubtitle = app("iterm", "iTerm", subtitle: "Terminal emulator")
        let result = sections("terminal", [byKeyword, bySubtitle, terminal])
        let rows = result.first { $0.kind == .results }?.rows ?? []
        #expect(rows.map { $0.item.title } == ["Terminal", "iTerm", "Warp"])
        let full = SearchMatcher.match("terminal", in: "Terminal")!.score
        #expect(rows.map { $0.score } == [1_000_000 + full * 1_000, 1_000_000 + full / 2 * 1_000, 1_000_000 + full / 2 * 1_000])
        #expect(rows[0].titleRanges.count == 1)
        #expect(rows[1].titleRanges.isEmpty)
    }

    @Test("frecency breaks equal matches; then title, then id")
    func frecencyAndTies() {
        let one = app("one", "Notes One")
        let two = app("two", "Notes Two")
        #expect(titles(sections("notes", [two, one]), .results) == ["Notes One", "Notes Two"])
        let ranked = sections("notes", [one, two], usage: [two.id: used(1)])
        #expect(titles(ranked, .results) == ["Notes Two", "Notes One"])

        let first = app("a", "Same")
        let second = app("b", "Same")
        let ids = sections("same", [second, first]).first?.rows.map { $0.item.id.rawValue }
        #expect(ids == ["app:a", "app:b"])
    }

    @Test("favorites get a 50 point bonus in results, less than one recent use")
    func favoritesBonus() {
        let one = app("one", "Notes One")
        let two = app("two", "Notes Two")
        var settings = CastSettings()
        settings.favorites = [two.id]
        let rows = sections("notes", [one, two], settings: settings).first { $0.kind == .results }?.rows ?? []
        #expect(rows.map { $0.item.title } == ["Notes Two", "Notes One"])
        #expect(rows.map { $0.score - rows[1].score } == [50, 0])

        let withUsage = sections("notes", [one, two], settings: settings, usage: [one.id: used(1)])
        #expect(titles(withUsage, .results) == ["Notes One", "Notes Two"])
    }

    @Test("disabled items appear nowhere")
    func disabledExcluded() {
        let chrome = app("com.google.Chrome", "Google Chrome")
        let google = CastItem(id: searchGoogle, title: "Search Google", icon: .glyph(.magnifier))
        var settings = CastSettings()
        settings.favorites = [chrome.id]
        settings.aliases = [chrome.id: "gc"]
        settings.disabled = [chrome.id, searchGoogle]
        let usage = [chrome.id: used(3)]
        #expect(sections("", [chrome, google], settings: settings, usage: usage).isEmpty)
        #expect(sections("gc", [chrome, google], settings: settings, usage: usage).isEmpty)
        #expect(sections("chrome", [chrome, google], settings: settings, usage: usage).isEmpty)
    }

    @Test("no match means no row, and results stop at 60")
    func excludedAndCapped() {
        let items = (0..<70).map { app("item\($0)", "Item \($0)") }
        var settings = CastSettings()
        settings.fallbacks = []
        #expect(sections("zzz", items, settings: settings).isEmpty)
        #expect(sections("item", items).first { $0.kind == .results }?.rows.count == Ranker.maxResults)
        #expect(Ranker.maxResults == 60)
    }

    // MARK: Empty query

    @Test("an empty query shows favorites in settings order, skipping missing and disabled ones")
    func emptyQueryFavorites() {
        let chrome = app("com.google.Chrome", "Google Chrome")
        let notes = app("com.apple.Notes", "Notes")
        let mail = app("com.apple.mail", "Mail")
        var settings = CastSettings()
        settings.favorites = [notes.id, ItemID(kind: .application, key: "gone"), mail.id, chrome.id]
        settings.disabled = [mail.id]
        let result = sections("  ", [chrome, notes, mail], settings: settings)
        #expect(result.map { $0.kind } == [.favorites])
        #expect(titles(result, .favorites) == ["Notes", "Google Chrome"])
    }

    @Test("suggestions are the six most frecent used items that aren't favorites")
    func emptyQuerySuggestions() {
        let items = (0..<9).map { app("app\($0)", "App \($0)") }
        var settings = CastSettings()
        settings.favorites = [items[8].id]
        var usage: [ItemID: UsageRecord] = [:]
        for index in 1...8 {
            usage[items[index].id] = used(index)
        }
        usage[items[0].id] = UsageRecord()
        let result = sections("", items, settings: settings, usage: usage)
        #expect(result.map { $0.kind } == [.favorites, .suggestions])
        #expect(titles(result, .suggestions) == ["App 7", "App 6", "App 5", "App 4", "App 3", "App 2"])
    }

    @Test("an empty query without favorites or usage shows nothing")
    func emptyQueryNothing() {
        #expect(sections("", [app("a", "A")]).isEmpty)
    }

    // MARK: Calculator and fallbacks

    @Test("the calculator row comes first, as a calculator item")
    func calculatorFirst() {
        let calc = CalculatorResult(expression: "2+2", value: 4, formatted: "4")
        let google = CastItem(id: searchGoogle, title: "Search Google", icon: .glyph(.magnifier))
        let result = sections("2+2", [google, app("two", "2+2 Notes")], calculator: calc)
        #expect(result.map { $0.kind } == [.calculator, .results, .fallbacks])
        let row = result[0].rows
        #expect(row.count == 1)
        #expect(row.first?.item == CastItem(id: .calculatorResult, title: "4", subtitle: "2+2", icon: .glyph(.calculator)))
        #expect(row.first?.item.kind == .calculator)
    }

    @Test("fallbacks come last, only with a query, in settings order, existing and enabled")
    func fallbacks() {
        let google = CastItem(id: searchGoogle, title: "Search Google", icon: .glyph(.magnifier))
        let duck = CastItem(id: ItemID(kind: .quicklink, key: "duck"), title: "DuckDuckGo", icon: .glyph(.link))
        let wiki = CastItem(id: ItemID(kind: .quicklink, key: "wiki"), title: "Wikipedia", icon: .glyph(.link))
        let items = [google, duck, wiki, app("chrome", "Google Chrome")]
        var settings = CastSettings()
        settings.fallbacks = [duck.id, ItemID(kind: .quicklink, key: "gone"), wiki.id, searchGoogle]
        settings.disabled = [wiki.id]

        #expect(sections("", items, settings: settings).isEmpty)
        let result = sections("google", items, settings: settings)
        #expect(result.map { $0.kind } == [.results, .fallbacks])
        #expect(titles(result, .fallbacks) == ["DuckDuckGo", "Search Google"])
        #expect(sections("zzz", items, settings: settings).map { $0.kind } == [.fallbacks])
    }
}
