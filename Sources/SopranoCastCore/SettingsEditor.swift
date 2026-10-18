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
}
