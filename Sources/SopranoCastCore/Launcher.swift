import Foundation

// Value types shared by the ranker, the launcher key router, the recorder and the UI.

public enum SectionKind: String, CaseIterable, Sendable {
    case calculator
    case favorites
    case suggestions
    case results
    case fallbacks

    public var title: String {
        switch self {
        case .calculator: "calculator"
        case .favorites: "favorites"
        case .suggestions: "suggestions"
        case .results: "results"
        case .fallbacks: "use with"
        }
    }
}

/// One row the ranker produced.
public struct RankedItem: Hashable, Sendable {
    public var item: CastItem
    public var score: Int
    /// Matched character ranges in `item.title`, for highlighting.
    public var titleRanges: [Range<String.Index>]
    /// The query matched the item's alias exactly or by prefix.
    public var matchedAlias: Bool

    public init(item: CastItem, score: Int, titleRanges: [Range<String.Index>] = [], matchedAlias: Bool = false) {
        self.item = item
        self.score = score
        self.titleRanges = titleRanges
        self.matchedAlias = matchedAlias
    }
}

public struct ResultSection: Hashable, Sendable {
    public var kind: SectionKind
    public var rows: [RankedItem]

    public init(kind: SectionKind, rows: [RankedItem]) {
        self.kind = kind
        self.rows = rows
    }
}

/// A row in the Action Panel.
public struct ItemAction: Hashable, Sendable {
    public var id: ItemActionID
    public var title: String
    /// The in-launcher shortcut shown at the trailing edge and handled in Root Search.
    public var shortcut: HotkeyCombo?
    public var isDestructive: Bool

    public init(id: ItemActionID, title: String, shortcut: HotkeyCombo? = nil, isDestructive: Bool = false) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.isDestructive = isDestructive
    }
}

/// What the launcher shows on top of Root Search; decides how keys are routed.
public enum LauncherContext: Equatable, Sendable {
    /// Root Search. `argumentFocused` while an argument field has focus.
    case root(argumentFocused: Bool)
    /// The ⌘K Action Panel (also the Configure Command submenu).
    case actionPanel
    case hotkeyRecorder
    case aliasEditor
    /// Script output (fullOutput mode).
    case output
    case confirmation
}

/// What a key does in the launcher (`LauncherKeyRouter`).
public enum LauncherCommand: Equatable, Sendable {
    case moveUp
    case moveDown
    case pageUp
    case pageDown
    case sectionUp
    case sectionDown
    /// ↑ at the top of the list / ↓ at the bottom: step through past queries.
    case historyPrevious
    case historyNext
    case runPrimary
    case runSecondary
    case runTertiary
    case toggleActionPanel
    /// ⇧⌘, — opens the Configure Command menu for the selection.
    case configureCommand
    case toggleFavorite
    case moveFavoriteUp
    case moveFavoriteDown
    case disableCommand
    /// An item action bound to an in-launcher shortcut (⌘O, ⇧⌘O, ⌘C …).
    case runAction(ItemActionID)
    /// Esc: back out of the current view; from Root Search, close the window.
    case back
    case popToRoot
    case closeWindow
    case openSettings
    /// Tab / ⇧Tab between argument fields.
    case nextArgument
    case previousArgument
}

/// The recorder's state after one key event (`HotkeyRecorder`).
public enum RecorderUpdate: Equatable, Sendable {
    /// Keys are down; `display` is what to show as keycaps ("⌘", "⇧", "K").
    case pending(display: [String])
    /// A complete hotkey; the UI starts the 1.5 s auto-save countdown.
    case recorded(HotkeySpec)
    /// Backspace without modifiers: remove the hotkey.
    case cleared
    /// Escape without modifiers: leave without changes.
    case cancelled
    /// Return without modifiers: save what was recorded now.
    case commit
    /// The event changed nothing visible.
    case unchanged
}

/// How running an item ended, for the launcher to present.
public enum RunOutcome: Equatable, Sendable {
    /// Done; close the launcher when `closeLauncher`.
    case done(closeLauncher: Bool)
    /// Close the launcher and show a short floating message (script `silent` mode, copy).
    case hud(String)
    /// Stay open and show a message in the footer (script `compact` mode).
    case toast(String, isError: Bool)
    /// Show text in the output view (script `fullOutput` mode).
    case output(title: String, text: String, isError: Bool)
}

/// One calculator answer.
public struct CalculatorResult: Equatable, Sendable {
    public var expression: String
    public var value: Double
    /// Locale-aware, at most 10 significant fraction digits, no trailing zeros.
    public var formatted: String

    public init(expression: String, value: Double, formatted: String) {
        self.expression = expression
        self.value = value
        self.formatted = formatted
    }
}

/// Item usage for frecency ranking: the newest use times, newest first (at most 10).
public struct UsageRecord: Codable, Equatable, Sendable {
    public var uses: [Date]

    public init(uses: [Date] = []) {
        self.uses = uses
    }
}
