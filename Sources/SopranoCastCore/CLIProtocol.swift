import Foundation

// Messages between `SopranoCast <command>` and the running app, JSON over the
// CFMessagePort "<bundle id>.cli" (CLIServer / CLIClient in the app target).
// `import-raycast` does not use the port: it edits settings.json directly and the
// running app reloads it.

public enum CLIRequest: Codable, Equatable, Sendable {
    case toggleLauncher
    /// Runs an item as its hotkey would; `arguments` fill its argument fields in order.
    case open(itemID: String, arguments: [String])
    case list
}

/// One item in `list` output.
public struct CLIItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: String
    public var subtitle: String
    /// The hotkey's settings spelling ("cmd+1"), if any.
    public var hotkey: String?
    public var alias: String?
    public var favorite: Bool
    public var disabled: Bool

    public init(id: String, title: String, kind: String, subtitle: String, hotkey: String?, alias: String?, favorite: Bool, disabled: Bool) {
        self.id = id
        self.title = title
        self.kind = kind
        self.subtitle = subtitle
        self.hotkey = hotkey
        self.alias = alias
        self.favorite = favorite
        self.disabled = disabled
    }
}

public struct CLIResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?
    public var items: [CLIItem]?

    public init(ok: Bool, error: String? = nil, items: [CLIItem]? = nil) {
        self.ok = ok
        self.error = error
        self.items = items
    }
}
