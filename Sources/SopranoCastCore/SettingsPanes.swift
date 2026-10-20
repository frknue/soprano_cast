import Foundation

// System Settings panes as Root Search items (`pane:<bundle id>`), like Raycast's System
// Settings extension. Built-in panes are ExtensionKit `.appex` bundles in
// /System/Library/ExtensionKit/Extensions; third-party panes are legacy `.prefPane`
// bundles. These functions only read the bundles' already-decoded plists; the app scans.

/// What the Mac is, for the `predicate`s of a pane's `representations`.
public struct SettingsPaneFacts: Equatable, Sendable {
    /// Known predicate keys → value, e.g. "powersource.battery", "device.touchID", "user.isguest", "device.cddvd".
    public var values: [String: Bool]

    public init(values: [String: Bool] = [:]) {
        self.values = values
    }
}

/// How a pane item opens.
public enum SettingsPaneTarget: Equatable, Sendable {
    case url(String)    // "x-apple.systempreferences:<key>"
    case file(String)   // a .prefPane path, opened with NSWorkspace
}

public enum SettingsPanes {
    public static let extensionPoint: String = "com.apple.Settings.extension.ui"
    public static let subtitle: String = "System Settings"
    /// The loctable entry naming each string's source, not a locale.
    public static let provenanceKey: String = "LocProvenance"

    /// One `.appex` → item. `info` = Contents/Info.plist; `infoStrings` / `localizable` = the decoded
    /// Contents/Resources/InfoPlist.loctable / Localizable.loctable (locale code → table; [:] when absent);
    /// `preferredLanguages` = Locale.preferredLanguages; `preference(domain, key)` reads a Bool default (nil when unset).
    ///
    /// Nil for other extension points, panes System Settings can't open by URL, panes their
    /// `representations` hide on this Mac and internal names ending in "Extension". The title
    /// is the shown representation's sidebar name, else the localized bundle name; keywords
    /// add the English name and the title with plain hyphens and spaces.
    public static func extensionItem(path: String, info: [String: Any], infoStrings: [String: [String: Any]],
                                     localizable: [String: [String: Any]], preferredLanguages: [String],
                                     facts: SettingsPaneFacts,
                                     preference: (_ domain: String, _ key: String) -> Bool?) -> CastItem? {
        guard let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
              attributes["EXExtensionPointIdentifier"] as? String == extensionPoint,
              let id = trimmed(info["CFBundleIdentifier"]),
              let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
              settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true
        else { return nil }

        var sidebarName: String?
        if let shown = shownRepresentation(settings["representations"], facts: facts, preference: preference) {
            if shown["hidden"] as? Bool == true { return nil }
            sidebarName = trimmed(shown["sidebar-name"])
        }
        func name(table: ([String: [String: Any]]) -> [String: Any]?) -> String? {
            if let sidebarName {
                return trimmed(table(localizable)?[sidebarName]) ?? sidebarName
            }
            return trimmed(table(infoStrings)?["CFBundleDisplayName"])
                ?? trimmed(info["CFBundleDisplayName"])
                ?? trimmed(info["CFBundleName"])
        }

        guard let title = name(table: { preferredTable(in: $0, preferredLanguages: preferredLanguages) }),
              isListable(title)
        else { return nil }
        var keywords: [String] = []
        func addKeyword(_ word: String?) {
            guard let word, word != title, isListable(word), !keywords.contains(word) else { return }
            keywords.append(word)
        }
        addKeyword(name(table: englishTable))
        addKeyword(plainPunctuation(title))
        return paneItem(key: id, title: title, keywords: keywords, path: path)
    }

    /// One third-party `.prefPane` (from /Library/PreferencePanes, ~/Library/PreferencePanes) → item.
    ///
    /// Named by its localized `CFBundleDisplayName`, `NSPrefPaneIconLabel` or `CFBundleName`,
    /// else its file name; keyed by its bundle identifier, else its path.
    public static func legacyItem(path: String, info: [String: Any], infoStrings: [String: [String: Any]],
                                  preferredLanguages: [String]) -> CastItem? {
        guard isPrefPane(path), let key = trimmed(info["CFBundleIdentifier"]) ?? trimmed(path) else { return nil }
        let strings = preferredTable(in: infoStrings, preferredLanguages: preferredLanguages)
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = ["CFBundleDisplayName", "NSPrefPaneIconLabel", "CFBundleName"].lazy
            .compactMap { trimmed(strings?[$0]) ?? trimmed(info[$0]) }
            .first ?? trimmed(fileName)
        // Icon labels of old panes break lines ("Flash\nPlayer").
        guard let title = name?.components(separatedBy: .newlines).joined(separator: " ") else { return nil }
        return paneItem(key: key, title: title, keywords: [], path: path)
    }

    /// How to open a `.settingsPane` item: `.file(path)` when its icon path ends in ".prefPane", else
    /// `.url("x-apple.systempreferences:" + id.key)`; nil for other kinds.
    public static func target(for item: CastItem) -> SettingsPaneTarget? {
        guard item.kind == .settingsPane else { return nil }
        if case .file(let path) = item.icon, isPrefPane(path) { return .file(path) }
        return .url("x-apple.systempreferences:" + item.id.key)
    }

    private static func paneItem(key: String, title: String, keywords: [String], path: String) -> CastItem {
        CastItem(
            id: ItemID(kind: .settingsPane, key: key),
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            icon: .file(path: path)
        )
    }

    private static func isPrefPane(_ path: String) -> Bool {
        (path as NSString).pathExtension.caseInsensitiveCompare("prefPane") == .orderedSame
    }

    /// The first representation whose predicate is definitely true on this Mac; nil when
    /// none is (unknown facts never decide).
    private static func shownRepresentation(_ value: Any?, facts: SettingsPaneFacts,
                                            preference: (String, String) -> Bool?) -> [String: Any]? {
        guard let representations = value as? [Any] else { return nil }
        return representations.lazy
            .compactMap { $0 as? [String: Any] }
            .first { evaluate($0, facts: facts, preference: preference) == true }
    }

    /// A representation's `"<key> == YES"` / `"<key> != YES"` predicate; nil when undetermined.
    /// A key read from preferences counts as NO while unset (as System Settings' NSPredicate
    /// does); a key that is neither a fact nor a preference is undetermined.
    private static func evaluate(_ representation: [String: Any], facts: SettingsPaneFacts,
                                 preference: (String, String) -> Bool?) -> Bool? {
        guard let predicate = representation["predicate"] as? String else { return nil }
        let parts = predicate.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 3, parts[2] == "YES", parts[1] == "==" || parts[1] == "!=" else { return nil }
        let key = parts[0]
        var value = facts.values[key]
        for case let source as [String: Any] in representation["values_from_preferences"] as? [Any] ?? [] where value == nil {
            guard source["key"] as? String == key, let domain = source["domain"] as? String else { continue }
            value = preference(domain, key) ?? false
        }
        guard let value else { return nil }
        return parts[1] == "==" ? value : !value
    }

    /// The loctable for the user's languages, else the English one.
    private static func preferredTable(in tables: [String: [String: Any]], preferredLanguages: [String]) -> [String: Any]? {
        let locales = tables.keys.filter { $0 != provenanceKey }
        if let locale = Bundle.preferredLocalizations(from: locales, forPreferences: preferredLanguages).first,
           let table = tables[locale] {
            return table
        }
        return englishTable(in: tables)
    }

    private static func englishTable(in tables: [String: [String: Any]]) -> [String: Any]? {
        let locale = ["en", "en_US", "en_GB"].first { tables[$0] != nil }
            ?? tables.keys.sorted().first { $0.hasPrefix("en") }
        return locale.flatMap { tables[$0] }
    }

    /// Internal bundle names ("HeadphoneSettingsExtension") aren't pane names.
    private static func isListable(_ name: String) -> Bool {
        !name.hasSuffix("Extension")
    }

    /// "Wi‑Fi" (U+2011) → "Wi-Fi", so typing a plain hyphen finds it.
    private static func plainPunctuation(_ title: String) -> String {
        title.replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
