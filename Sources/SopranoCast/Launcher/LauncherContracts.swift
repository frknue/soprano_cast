import AppKit
import SopranoCastCore

// The seam between `LauncherController` (state, ranking, keys, running, settings writes)
// and `LauncherWindow` (the panel and everything drawn in it). The controller builds a
// `LauncherViewModel`; the presenter renders it and reports keys, text and clicks back.

struct RowViewModel {
    var id: ItemID
    var title: String
    var titleHighlights: [NSRange]
    var subtitle: String
    var icon: NSImage
    /// Trailing type label ("Application", "Command", a calculator's expression).
    var accessory: String
    /// Shown as a badge after the title.
    var alias: String?
    /// The item's global hotkey as keycaps ("⌘", "1"); the view shows it on the selected row.
    var hotkeyKeys: [String]
}

struct SectionViewModel {
    var title: String
    var rows: [RowViewModel]
}

struct ArgumentFieldViewModel {
    var placeholder: String
    var value: String
    var isSecure: Bool
    /// Dropdown titles; nil for a text field.
    var options: [String]?
    var isOptional: Bool
}

struct ActionRowViewModel {
    var title: String
    /// Shortcut keycaps ("⇧", "⌘", "O"); empty when the action has none.
    var keys: [String]
    var isDestructive: Bool
}

/// What sits on top of Root Search.
enum OverlayViewModel {
    case none
    /// The ⌘K Action Panel or the Configure Command submenu; `query` filters it.
    case actionPanel(title: String, query: String, rows: [ActionRowViewModel], selectedIndex: Int?)
    /// The hotkey recorder: keycaps so far, an owner conflict, the auto-save countdown
    /// progress (0…1, nil when not counting down), and a hint line.
    case recorder(itemTitle: String, keys: [String], conflict: String?, countdown: Double?, hint: String)
    case aliasEditor(itemTitle: String, text: String, error: String?)
    /// Script output (fullOutput mode), monospace.
    case output(title: String, text: String, isError: Bool)
    case confirmation(title: String, message: String, confirmTitle: String)
}

struct FooterViewModel {
    /// A toast replaces the left side for a few seconds.
    var toast: String?
    var toastIsError: Bool
    /// The primary action's title ("Open Application") with ↵.
    var primaryTitle: String?
    /// "Actions" with ⌘K, shown when the selection has actions.
    var showsActions: Bool
}

/// Which text field has keyboard focus.
enum LauncherFocus: Equatable {
    case query
    case argument(Int)
    /// The overlay's text field (Action Panel filter, alias editor).
    case overlay
    /// No text field (recorder, output, confirmation).
    case none
}

struct LauncherViewModel {
    var theme: AppTheme
    var query: String
    var placeholder: String
    var arguments: [ArgumentFieldViewModel]
    var sections: [SectionViewModel]
    /// Flat index over every section's rows; nil when there are none.
    var selectedIndex: Int?
    var footer: FooterViewModel
    var overlay: OverlayViewModel
    var focus: LauncherFocus
    /// Shown instead of rows when every section is empty.
    var emptyText: String?
}

/// Draws the launcher.
@MainActor
protocol LauncherPresenting: AnyObject {
    var isPresented: Bool { get }
    /// How many rows fit in the list (for ⌥↑/⌥↓ page jumps).
    var visibleRowCount: Int { get }
    /// Shows the panel on the display whose AppKit visible frame is `screenFrame`
    /// (centered horizontally, its top a fifth down the display), key without activating
    /// Soprano Cast; or redraws it when already shown.
    func present(_ model: LauncherViewModel, screenFrame: CGRect)
    func update(_ model: LauncherViewModel)
    func dismiss()
    /// A short floating message near the bottom of the display, gone after ~1.5 s.
    func showHUD(_ text: String, screenFrame: CGRect)

    /// Every keyDown and flagsChanged while the panel is key, before any text field sees it.
    /// Return true when handled; unhandled keys go to the focused text field.
    var onKeyEvent: ((KeyEvent) -> Bool)? { get set }
    var onQueryChange: ((String) -> Void)? { get set }
    var onArgumentChange: ((Int, String) -> Void)? { get set }
    /// The overlay's text changed (Action Panel filter, alias editor).
    var onOverlayTextChange: ((String) -> Void)? { get set }
    /// A row was clicked (flat index, click count).
    var onRowClick: ((Int, Int) -> Void)? { get set }
    var onActionClick: ((Int) -> Void)? { get set }
    /// The panel lost key status (another app was clicked).
    var onResignKey: (() -> Void)? { get set }

    /// Renders a `screenFrame`-sized image of `backdrop` (or the theme's base color) with
    /// the panel (and HUD) where they would appear. For the snapshot harness; offscreen.
    func renderSnapshot(screenFrame: CGRect, scale: CGFloat, backdrop: CGImage?) -> CGImage?
}

/// A settings.json change the launcher or the settings window makes.
enum SettingsEdit {
    /// Sets a JSON value (Bool, Int, String, [Any], [String: Any], NSNull) at a key path.
    case set(Any, [String])
    case remove([String])
    /// Writes the "quicklinks" entry with this id (appending it when new), or removes it
    /// with nil fields; every other entry stays as written.
    case quicklink(id: String, fields: QuicklinkFields?)
}

/// What `LauncherController` needs from the app; injectable for tests and the harness.
struct LauncherEnvironment {
    var settings: @MainActor () -> CastSettings
    var editSettings: @MainActor (SettingsEdit) throws -> Void
    var theme: @MainActor () -> AppTheme
    var now: @MainActor () -> Date
    /// Runs `work` after `milliseconds` on the main actor; returns a cancel closure.
    var schedule: @MainActor (_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> (() -> Void)
    /// The AppKit visible frame of the display `LauncherScreen` picks.
    var screenFrame: @MainActor (LauncherScreen) -> CGRect
    var loadUsage: @MainActor () -> [ItemID: UsageRecord]
    var saveUsage: @MainActor ([ItemID: UsageRecord]) -> Void
    var loadHistory: @MainActor () -> [String]
    var saveHistory: @MainActor ([String]) -> Void
}
