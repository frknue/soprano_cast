import Foundation

/// Soprano's `appearance` key: the app follows the system, or is pinned light or dark.
public enum SopranoAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// The two keys of Soprano's settings.json that Cast follows with `theme: "soprano"`.
/// Every other Soprano key is ignored.
public struct SopranoThemeSettings: Equatable, Sendable {
    /// The theme id as written; nil when missing or not a string. Unknown ids are the
    /// caller's to resolve (they fall back to Folio).
    public var theme: String?
    /// `.system` when missing or not one of "system", "light", "dark".
    public var appearance: SopranoAppearance

    public init(theme: String? = nil, appearance: SopranoAppearance = .system) {
        self.theme = theme
        self.appearance = appearance
    }

    /// Reads JSONC text (comments, trailing commas); nil when it is not a JSON object.
    public static func read(text: String) -> SopranoThemeSettings? {
        guard let data = try? JSONCText.strictJSONData(from: text),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]
        else { return nil }
        return SopranoThemeSettings(
            theme: root["theme"] as? String,
            appearance: (root["appearance"] as? String).flatMap(SopranoAppearance.init(rawValue:)) ?? .system
        )
    }
}
