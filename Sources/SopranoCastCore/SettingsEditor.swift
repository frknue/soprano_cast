import Foundation

/// A settings.json edit that could not be applied, positioned in the original text.
public struct SettingsEditError: Error, Equatable {
    public let message: String
    /// 1-based line in the edited document.
    public let line: Int

    public init(message: String, line: Int) {
        self.message = message
        self.line = line
    }
}

/// Surgical writes into settings.json that keep the user's comments and layout (hotkeys
/// and aliases set from the Action Panel land here).
public enum SettingsEditor {
    /// Sets `value` (Bool, Int, Double, String, [Any], [String: Any], NSNull) at `path`,
    /// keeping comments and key order; missing objects on the way are created (wraps the
    /// vendored `JSONCText.setting`). Throws `SettingsEditError` when the document is not
    /// a JSON object.
    public static func setting(_ value: Any, at path: [String], in text: String) throws -> String {
        do {
            return try JSONCText.setting(value, at: path, in: text)
        } catch let error as JSONCText.ParseError {
            throw SettingsEditError(message: error.message, line: error.line)
        }
    }

    /// Removes the key at `path`, keeping every other key and comment; returns `text`
    /// unchanged when the key is absent. Throws `SettingsEditError` when the document is
    /// not a JSON object.
    public static func removing(at path: [String], in text: String) throws -> String {
        do {
            return try JSONCText.removing(at: path, in: text)
        } catch let error as JSONCText.ParseError {
            throw SettingsEditError(message: error.message, line: error.line)
        }
    }

    /// Writes `fields` into the "quicklinks" entry whose id is `id` (the entry's other keys
    /// and every other entry stay as written, even ones the resolver drops), or appends a
    /// new entry. Fields are trimmed; a blank `openWith` or `icon` removes the key.
    public static func settingQuicklink(_ fields: QuicklinkFields, id: String, in text: String) throws -> String {
        var entries = try rawQuicklinks(in: text)
        if let index = entries.firstIndex(where: { quicklinkID(of: $0) == id }), var entry = entries[index] as? [String: Any] {
            fields.write(into: &entry)
            entries[index] = entry
        } else {
            var entry: [String: Any] = ["id": id]
            fields.write(into: &entry)
            entries.append(entry)
        }
        return try setting(entries, at: ["quicklinks"], in: text)
    }

    /// Removes every "quicklinks" entry whose id is `id`; `text` unchanged when none has it.
    public static func removingQuicklink(id: String, in text: String) throws -> String {
        let entries = try rawQuicklinks(in: text)
        let kept = entries.filter { quicklinkID(of: $0) != id }
        guard kept.count != entries.count else { return text }
        return try setting(kept, at: ["quicklinks"], in: text)
    }

    /// The document's "quicklinks" array as written; empty when it is missing or no array.
    private static func rawQuicklinks(in text: String) throws -> [Any] {
        let root: Any
        do {
            let data = try JSONCText.strictJSONData(from: text)
            root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch let error as JSONCText.ParseError {
            throw SettingsEditError(message: error.message, line: error.line)
        }
        guard let object = root as? [String: Any] else {
            throw SettingsEditError(message: "settings.json must be a JSON object", line: 1)
        }
        return object["quicklinks"] as? [Any] ?? []
    }

    private static func quicklinkID(of entry: Any) -> String? {
        (entry as? [String: Any])?["id"] as? String
    }
}

/// A quicklink's fields as the settings window edits them.
public struct QuicklinkFields: Equatable, Sendable {
    public var name: String
    /// URL, path or deeplink with `{argument}` placeholders.
    public var link: String
    /// Bundle id, app name or path; blank opens the link's default app.
    public var openWith: String
    /// An emoji or image path; blank draws the link glyph.
    public var icon: String

    public init(name: String = "", link: String = "", openWith: String = "", icon: String = "") {
        self.name = name
        self.link = link
        self.openWith = openWith
        self.icon = icon
    }

    public init(_ quicklink: Quicklink) {
        self.init(name: quicklink.name, link: quicklink.link, openWith: quicklink.openWith ?? "", icon: quicklink.icon ?? "")
    }

    /// Why the quicklink can't be saved yet; nil when it can.
    public var problem: String? {
        if Self.trimmed(name).isEmpty { return "A quicklink needs a name" }
        if Self.trimmed(link).isEmpty { return "A quicklink needs a link" }
        return nil
    }

    fileprivate func write(into entry: inout [String: Any]) {
        entry["name"] = Self.trimmed(name)
        entry["link"] = Self.trimmed(link)
        for (key, value) in [("openWith", openWith), ("icon", icon)] {
            let text = Self.trimmed(value)
            entry[key] = text.isEmpty ? nil : text
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
