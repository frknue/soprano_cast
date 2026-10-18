import Foundation

// Resolved settings: ~/.config/soprano-cast/settings.json over these defaults
// (`SettingsResolver`). Raw values are the settings.json spellings.

/// Where the launcher opens.
public enum LauncherScreen: String, CaseIterable, Sendable {
    /// The display containing the mouse.
    case withMouse
    /// The display of the frontmost window.
    case withActiveWindow
    /// The primary display.
    case primary
}

/// Extra list navigation keys besides ↑ ↓.
public enum NavigationBindings: String, CaseIterable, Sendable {
    /// ⌃N / ⌃P (Raycast's default).
    case emacs
    /// ⌃J / ⌃K.
    case vim
    /// Both.
    case both
}

public struct LauncherSettings: Equatable, Sendable {
    /// Opens and closes the launcher. nil = no global launcher hotkey.
    public var hotkey: HotkeySpec? = .combo(HotkeyCombo(modifiers: .command, key: .named(.space)))
    public var screen: LauncherScreen = .withMouse
    /// Reopening later than this clears the search and returns to Root Search. 0 = immediately.
    public var popToRootSeconds = 90
    public var navigation: NavigationBindings = .emacs
    /// Clicking another app closes the launcher.
    public var closeOnFocusLoss = true

    public init() {}

    public static let popToRootRange = 0...3600
}

/// The physical key that becomes the Hyper key.
public enum HyperTrigger: String, CaseIterable, Sendable {
    case capsLock
    case rightCommand
    case rightOption
    case rightControl
    case rightShift
    case f18
}

/// What tapping the Hyper key alone does (Caps Lock trigger only).
public enum HyperQuickPress: String, CaseIterable, Sendable {
    case nothing
    case toggleCapsLock
    case escape
}

public struct HyperKeySettings: Equatable, Sendable {
    /// nil = no Hyper key.
    public var trigger: HyperTrigger?
    public var includeShift = true
    public var quickPress: HyperQuickPress = .nothing

    public init(trigger: HyperTrigger? = nil, includeShift: Bool = true, quickPress: HyperQuickPress = .nothing) {
        self.trigger = trigger
        self.includeShift = includeShift
        self.quickPress = quickPress
    }
}

/// What pressing Left/Right Half again does.
public enum HalvesBehavior: String, CaseIterable, Sendable {
    /// Nothing more: the window stays a half.
    case stay
    /// ½ → ⅔ → ⅓ → ½.
    case cycleSizes
    /// Already the left half: move to the right half of the display to the left.
    case moveToDisplay
}

public struct WindowManagementSettings: Equatable, Sendable {
    /// Points between windows and between windows and the display edge.
    public var gap = 0
    public var halves: HalvesBehavior = .stay

    public init(gap: Int = 0, halves: HalvesBehavior = .stay) {
        self.gap = gap
        self.halves = halves
    }

    public static let gapRange = 0...64
}

public struct AppBehaviorSettings: Equatable, Sendable {
    public var startAtLogin = true
    public var showMenuBarIcon = true

    public init(startAtLogin: Bool = true, showMenuBarIcon: Bool = true) {
        self.startAtLogin = startAtLogin
        self.showMenuBarIcon = showMenuBarIcon
    }
}

public struct CastSettings: Equatable, Sendable {
    /// A Soprano theme id, or "soprano" to follow ~/.config/soprano/settings.json.
    public var theme = "soprano"
    public var launcher = LauncherSettings()
    /// Global hotkeys per item.
    public var hotkeys: [ItemID: HotkeySpec] = [:]
    /// Root Search aliases per item: lowercase a–z, 0–9 and spaces.
    public var aliases: [ItemID: String] = [:]
    /// Root Search's Favorites section, in order.
    public var favorites: [ItemID] = []
    /// Items hidden from Root Search (hotkeys still work).
    public var disabled: Set<ItemID> = []
    /// Offered at the end of the results for any query ("Use “x” with …").
    public var fallbacks: [ItemID] = [ItemID(kind: .castCommand, key: CastCommand.searchGoogle.rawValue)]
    public var quicklinks: [Quicklink] = []
    /// Folders of Raycast-format script commands (~ allowed).
    public var scriptDirectories: [String] = []
    /// Extra folders searched for applications.
    public var applicationDirectories: [String] = []
    public var hyperKey = HyperKeySettings()
    public var windowManagement = WindowManagementSettings()
    public var app = AppBehaviorSettings()

    public init() {}

    public static let defaults = CastSettings()

    /// Every global hotkey to register: the launcher's plus each item's.
    public var hotkeyBindings: [HotkeyBinding] {
        var bindings: [HotkeyBinding] = []
        if let hotkey = launcher.hotkey { bindings.append(HotkeyBinding(spec: hotkey, target: .launcher)) }
        for (id, spec) in hotkeys.sorted(by: { $0.key < $1.key }) {
            bindings.append(HotkeyBinding(spec: spec, target: .item(id)))
        }
        return bindings
    }
}

/// A problem found while resolving settings.json. Issues never block startup: a bad
/// value keeps its default and is reported (Soprano's `ConfigIssue`).
public struct ConfigIssue: Equatable, Identifiable, Sendable {
    public enum Severity: Equatable, Sendable {
        /// The document could not be read at all; the last good settings stay in force.
        case error
        /// One key was ignored; everything else applied.
        case warning
    }

    public let severity: Severity
    public let message: String
    /// 1-based line in settings.json, when the problem has a position.
    public var line: Int?

    public init(severity: Severity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }

    public var id: String { "\(severity)-\(line ?? 0)-\(message)" }
}

/// The result of resolving settings.json text.
public struct SettingsResolution: Equatable, Sendable {
    /// nil when the document could not be parsed; `issues` then holds one `.error`.
    public var settings: CastSettings?
    public var issues: [ConfigIssue]

    public init(settings: CastSettings?, issues: [ConfigIssue]) {
        self.settings = settings
        self.issues = issues
    }
}
