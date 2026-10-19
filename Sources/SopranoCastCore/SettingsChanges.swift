import Foundation

// The settings.json values the launcher's actions and the settings window write, computed
// from the current settings so both write exactly the same thing.

extension CastSettings {
    /// `disabled` with `id` removed (`enabled`) or added, as sorted raw ids.
    public func disabledIDs(setting id: ItemID, enabled: Bool) -> [String] {
        var ids = disabled
        if enabled {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        return ids.map(\.rawValue).sorted()
    }

    /// `favorites` with `id` removed when it is one, else appended.
    public func favoriteIDs(toggling id: ItemID) -> [String] {
        Self.toggling(id, in: favorites)
    }

    /// `favorites` with `id` moved by `offset` places; nil when it can't move that far.
    public func favoriteIDs(moving id: ItemID, by offset: Int) -> [String]? {
        Self.moving(id, by: offset, in: favorites)
    }

    /// `fallbacks` with `id` removed when it is one, else appended.
    public func fallbackIDs(toggling id: ItemID) -> [String] {
        Self.toggling(id, in: fallbacks)
    }

    /// `fallbacks` with `id` moved by `offset` places; nil when it can't move that far.
    public func fallbackIDs(moving id: ItemID, by offset: Int) -> [String]? {
        Self.moving(id, by: offset, in: fallbacks)
    }

    private static func toggling(_ id: ItemID, in list: [ItemID]) -> [String] {
        var list = list
        if let index = list.firstIndex(of: id) {
            list.remove(at: index)
        } else {
            list.append(id)
        }
        return list.map(\.rawValue)
    }

    private static func moving(_ id: ItemID, by offset: Int, in list: [ItemID]) -> [String]? {
        var list = list
        guard let index = list.firstIndex(of: id), list.indices.contains(index + offset) else { return nil }
        list.swapAt(index, index + offset)
        return list.map(\.rawValue)
    }
}

/// Root Search aliases as settings.json accepts them.
public enum AliasText {
    public static let charactersError = "Use only a–z, 0–9 and spaces"

    /// Whether `text` uses only a–z, 0–9 and spaces (the resolver drops other aliases).
    public static func isValid(_ text: String) -> Bool {
        text.allSatisfy { SettingsResolver.aliasCharacters.contains($0) }
    }
}

/// Ids for quicklinks the settings window creates.
public enum QuicklinkID {
    /// The name's runs of a–z and 0–9 (lowercased, accents dropped) joined by "-"
    /// ("quicklink" when there are none), with "-2", "-3", … appended until it is unused.
    public static func make(for name: String, existing: Set<String>) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let runs = folded.lowercased()
            .split { !SettingsResolver.quicklinkIDCharacters.contains($0) || $0 == "-" }
            .map(String.init)
        let base = runs.isEmpty ? "quicklink" : runs.joined(separator: "-")
        guard existing.contains(base) else { return base }
        var number = 2
        while existing.contains("\(base)-\(number)") {
            number += 1
        }
        return "\(base)-\(number)"
    }
}
