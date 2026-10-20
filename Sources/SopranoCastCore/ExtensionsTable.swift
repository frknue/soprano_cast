import Foundation

/// A group of the settings window's Extensions table (Raycast's), in display order.
public enum ExtensionGroup: String, CaseIterable, Sendable {
    case applications
    case quicklinks
    case scriptCommands
    case sopranoCast
    case system
    case systemSettings
    case windowManagement

    /// The group an item kind is listed under; nil for the calculator (never stored).
    public init?(kind: ItemKind) {
        switch kind {
        case .application: self = .applications
        case .quicklink: self = .quicklinks
        case .script: self = .scriptCommands
        case .castCommand: self = .sopranoCast
        case .systemCommand: self = .system
        case .settingsPane: self = .systemSettings
        case .windowCommand: self = .windowManagement
        case .calculator: return nil
        }
    }

    public var title: String {
        switch self {
        case .applications: "Applications"
        case .quicklinks: "Quicklinks"
        case .scriptCommands: "Script Commands"
        case .sopranoCast: "Soprano Cast"
        case .system: "System"
        case .systemSettings: "System Settings"
        case .windowManagement: "Window Management"
        }
    }
}

/// One command of the Extensions table with what settings.json says about it.
public struct ExtensionRow: Equatable, Sendable {
    public var item: CastItem
    public var alias: String?
    public var hotkey: HotkeySpec?
    /// Listed in Root Search (not in `disabled`).
    public var isEnabled: Bool
    public var isFavorite: Bool
    public var isFallback: Bool

    public init(item: CastItem, settings: CastSettings) {
        self.item = item
        alias = settings.aliases[item.id]
        hotkey = settings.hotkeys[item.id]
        isEnabled = !settings.disabled.contains(item.id)
        isFavorite = settings.favorites.contains(item.id)
        isFallback = settings.fallbacks.contains(item.id)
    }

    /// Root Search's type label: "Application", "Command", "Quicklink", "Script Command".
    public var typeLabel: String { item.kind?.label ?? "" }
}

public struct ExtensionSection: Equatable, Sendable {
    public var group: ExtensionGroup
    public var rows: [ExtensionRow]

    public init(group: ExtensionGroup, rows: [ExtensionRow]) {
        self.group = group
        self.rows = rows
    }
}

public enum ExtensionsTable {
    /// Every item but the calculator, grouped in `ExtensionGroup` order and sorted by title
    /// (then id). Without a filter every group is listed, even an empty one (it is where
    /// quicklinks are created and script folders added). A filter keeps the rows whose
    /// title, subtitle, alias, type label or id contain each of its words (ignoring case
    /// and accents) and leaves out groups without any.
    public static func sections(items: [CastItem], settings: CastSettings, filter: String = "") -> [ExtensionSection] {
        let words = filter.split(whereSeparator: \.isWhitespace).map(String.init)
        var grouped: [ExtensionGroup: [ExtensionRow]] = [:]
        var seen: Set<ItemID> = []
        for item in items {
            guard let kind = item.kind, let group = ExtensionGroup(kind: kind), seen.insert(item.id).inserted else { continue }
            let row = ExtensionRow(item: item, settings: settings)
            guard words.allSatisfy({ matches(row, word: $0) }) else { continue }
            grouped[group, default: []].append(row)
        }
        return ExtensionGroup.allCases.compactMap { group in
            let rows = (grouped[group] ?? []).sorted { lhs, rhs in
                let order = lhs.item.title.localizedStandardCompare(rhs.item.title)
                return order == .orderedSame ? lhs.item.id < rhs.item.id : order == .orderedAscending
            }
            guard words.isEmpty || !rows.isEmpty else { return nil }
            return ExtensionSection(group: group, rows: rows)
        }
    }

    private static func matches(_ row: ExtensionRow, word: String) -> Bool {
        let fields = [row.item.title, row.item.subtitle, row.alias ?? "", row.typeLabel, row.item.id.rawValue]
        return fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
