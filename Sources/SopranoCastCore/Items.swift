import CoreGraphics
import Foundation

// Everything Root Search can list and every hotkey can run is a `CastItem`, named by a
// stable `ItemID`. Settings (hotkeys, aliases, favorites, disabled, fallbacks) refer to
// items by their id's raw string, so these spellings are part of the settings format.

/// A stable item identifier: "<kind>:<key>".
///
/// - `app:<bundle id>` (or `app:<absolute path>` for bundles without an id)
/// - `system:<SystemCommand raw value>`
/// - `window:<WindowCommand raw value>`
/// - `quicklink:<Quicklink.id>`
/// - `script:<absolute script path>`
/// - `cast:<CastCommand raw value>`
/// - `pane:<bundle id>` (a System Settings pane; `pane:<absolute path>` for a `.prefPane` without an id)
/// - `calculator:result` (the live calculator row; never stored in settings)
public struct ItemID: RawRepresentable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(kind: ItemKind, key: String) {
        rawValue = "\(kind.prefix):\(key)"
    }

    /// The kind named by the prefix; nil for an unknown prefix.
    public var kind: ItemKind? {
        guard let colon = rawValue.firstIndex(of: ":") else { return nil }
        return ItemKind(prefix: String(rawValue[..<colon]))
    }

    /// Everything after the first ":".
    public var key: String {
        guard let colon = rawValue.firstIndex(of: ":") else { return rawValue }
        return String(rawValue[rawValue.index(after: colon)...])
    }

    public var description: String { rawValue }

    public static func < (lhs: ItemID, rhs: ItemID) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let calculatorResult = ItemID(kind: .calculator, key: "result")
}

public enum ItemKind: String, CaseIterable, Sendable {
    case application
    case systemCommand
    case windowCommand
    case quicklink
    case script
    case castCommand
    case settingsPane
    case calculator

    public var prefix: String {
        switch self {
        case .application: "app"
        case .systemCommand: "system"
        case .windowCommand: "window"
        case .quicklink: "quicklink"
        case .script: "script"
        case .castCommand: "cast"
        case .settingsPane: "pane"
        case .calculator: "calculator"
        }
    }

    public init?(prefix: String) {
        guard let kind = ItemKind.allCases.first(where: { $0.prefix == prefix }) else { return nil }
        self = kind
    }

    /// The type label Root Search shows at the trailing edge of a row.
    public var label: String {
        switch self {
        case .application: "Application"
        case .systemCommand: "Command"
        case .windowCommand: "Command"
        case .quicklink: "Quicklink"
        case .script: "Script Command"
        case .castCommand: "Command"
        case .settingsPane: "Command"
        case .calculator: "Calculator"
        }
    }
}

/// What an item's icon is drawn from.
public enum ItemIcon: Hashable, Sendable {
    /// The icon of the bundle or file at this path (NSWorkspace).
    case file(path: String)
    /// A single emoji (script commands, quicklinks).
    case emoji(String)
    /// A remote PNG/JPEG (script commands' `https` icons), loaded and cached by the app.
    case url(URL)
    /// A built-in glyph drawn in the Soprano chrome: the raw value of `BuiltinGlyph`.
    case glyph(BuiltinGlyph)
}

/// Built-in icons drawn in code (no image assets).
public enum BuiltinGlyph: String, CaseIterable, Sendable {
    case power
    case lock
    case moon
    case display
    case trash
    case eject
    case appearance
    case quit
    case eyeSlash
    case window
    case link
    case script
    case gear
    case magnifier
    case calculator
    case refresh
}

/// One argument a quicklink or script command takes in Root Search (max three).
public struct ArgumentSpec: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case text
        case password
        /// A fixed list: (title, value) pairs.
        case dropdown([DropdownOption])
    }

    public struct DropdownOption: Hashable, Sendable {
        public var title: String
        public var value: String

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    public var name: String
    public var placeholder: String
    public var kind: Kind
    public var isOptional: Bool
    /// Percent-encode the value before substitution.
    public var percentEncoded: Bool

    public init(name: String, placeholder: String, kind: Kind = .text, isOptional: Bool = false, percentEncoded: Bool = false) {
        self.name = name
        self.placeholder = placeholder
        self.kind = kind
        self.isOptional = isOptional
        self.percentEncoded = percentEncoded
    }
}

/// One thing Root Search lists and a hotkey can run.
public struct CastItem: Hashable, Sendable, Identifiable {
    public var id: ItemID
    public var title: String
    /// Secondary text: an app's folder, a script's package name, a quicklink's link.
    public var subtitle: String
    /// Extra words search matches (not shown).
    public var keywords: [String]
    public var icon: ItemIcon
    public var arguments: [ArgumentSpec]
    /// Ask before running (Shut Down, Empty Trash, `needsConfirmation` scripts).
    public var needsConfirmation: Bool

    public init(
        id: ItemID,
        title: String,
        subtitle: String = "",
        keywords: [String] = [],
        icon: ItemIcon,
        arguments: [ArgumentSpec] = [],
        needsConfirmation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.icon = icon
        self.arguments = arguments
        self.needsConfirmation = needsConfirmation
    }

    public var kind: ItemKind? { id.kind }
}

/// Built-in system commands (`system:<rawValue>`).
public enum SystemCommand: String, CaseIterable, Sendable {
    case lockScreen
    case sleep
    case sleepDisplays
    case restart
    case shutDown
    case logOut
    case emptyTrash
    case ejectAllDisks
    case toggleSystemAppearance
    case quitAllApplications
    case hideOtherApplications
    case toggleHiddenFiles

    public var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleep: "Sleep"
        case .sleepDisplays: "Sleep Displays"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        case .logOut: "Log Out"
        case .emptyTrash: "Empty Trash"
        case .ejectAllDisks: "Eject All Disks"
        case .toggleSystemAppearance: "Toggle System Appearance"
        case .quitAllApplications: "Quit All Applications"
        case .hideOtherApplications: "Hide All Apps Except Frontmost"
        case .toggleHiddenFiles: "Toggle Hidden Files"
        }
    }

    public var needsConfirmation: Bool {
        switch self {
        case .restart, .shutDown, .logOut, .emptyTrash, .quitAllApplications: true
        default: false
        }
    }

    public var glyph: BuiltinGlyph {
        switch self {
        case .lockScreen: .lock
        case .sleep, .sleepDisplays: .moon
        case .restart, .shutDown, .logOut: .power
        case .emptyTrash: .trash
        case .ejectAllDisks: .eject
        case .toggleSystemAppearance: .appearance
        case .quitAllApplications: .quit
        case .hideOtherApplications, .toggleHiddenFiles: .eyeSlash
        }
    }
}

/// Built-in window management commands (`window:<rawValue>`), Raycast's set.
public enum WindowCommand: String, CaseIterable, Sendable {
    case toggleFullscreen
    case maximize
    case almostMaximize
    case maximizeHeight
    case maximizeWidth
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case centerHalf
    case center
    case moveUp
    case moveDown
    case moveLeft
    case moveRight
    case restore
    case reasonableSize
    case makeLarger
    case makeSmaller
    case firstThird
    case firstTwoThirds
    case centerThird
    case lastTwoThirds
    case lastThird
    case firstFourth
    case secondFourth
    case thirdFourth
    case lastFourth
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
    case previousDisplay
    case nextDisplay

    public var title: String {
        switch self {
        case .toggleFullscreen: "Toggle Fullscreen"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .maximizeHeight: "Maximize Height"
        case .maximizeWidth: "Maximize Width"
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .centerHalf: "Center Half"
        case .center: "Center"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .restore: "Restore"
        case .reasonableSize: "Reasonable Size"
        case .makeLarger: "Make Larger"
        case .makeSmaller: "Make Smaller"
        case .firstThird: "First Third"
        case .firstTwoThirds: "First Two Thirds"
        case .centerThird: "Center Third"
        case .lastTwoThirds: "Last Two Thirds"
        case .lastThird: "Last Third"
        case .firstFourth: "First Fourth"
        case .secondFourth: "Second Fourth"
        case .thirdFourth: "Third Fourth"
        case .lastFourth: "Last Fourth"
        case .topLeftQuarter: "Top Left Quarter"
        case .topRightQuarter: "Top Right Quarter"
        case .bottomLeftQuarter: "Bottom Left Quarter"
        case .bottomRightQuarter: "Bottom Right Quarter"
        case .topLeftSixth: "Top Left Sixth"
        case .topCenterSixth: "Top Center Sixth"
        case .topRightSixth: "Top Right Sixth"
        case .bottomLeftSixth: "Bottom Left Sixth"
        case .bottomCenterSixth: "Bottom Center Sixth"
        case .bottomRightSixth: "Bottom Right Sixth"
        case .previousDisplay: "Previous Display"
        case .nextDisplay: "Next Display"
        }
    }
}

/// Soprano Cast's own commands (`cast:<rawValue>`).
public enum CastCommand: String, CaseIterable, Sendable {
    case openSettings
    case reloadScripts
    case searchGoogle
    case searchDuckDuckGo
    case quit

    public var title: String {
        switch self {
        case .openSettings: "Soprano Cast Settings"
        case .reloadScripts: "Reload Script Directories"
        case .searchGoogle: "Search Google"
        case .searchDuckDuckGo: "Search DuckDuckGo"
        case .quit: "Quit Soprano Cast"
        }
    }

    public var glyph: BuiltinGlyph {
        switch self {
        case .openSettings: .gear
        case .reloadScripts: .refresh
        case .searchGoogle, .searchDuckDuckGo: .magnifier
        case .quit: .quit
        }
    }
}

/// A user quicklink from settings.json (`quicklink:<id>`).
public struct Quicklink: Hashable, Sendable {
    /// Unique, stable slug ([a-z0-9-]); the item id's key.
    public var id: String
    public var name: String
    /// URL, file/folder path (~ allowed) or deeplink, with placeholders:
    /// `{argument name="query"}`, `{argument}`, `{Query}`, `{clipboard}`, `{date}`, `{time}`, `{uuid}`.
    public var link: String
    /// Bundle id, app name or app path to open the link with; nil = system default.
    public var openWith: String?
    /// An emoji or image path; nil = link glyph (or the target app's icon).
    public var icon: String?

    public init(id: String, name: String, link: String, openWith: String? = nil, icon: String? = nil) {
        self.id = id
        self.name = name
        self.link = link
        self.openWith = openWith
        self.icon = icon
    }
}

/// A parsed Raycast-format script command (`script:<path>`).
public struct ScriptCommand: Hashable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case silent
        case compact
        case fullOutput
        case inline
    }

    public var path: String
    public var title: String
    public var mode: Mode
    public var packageName: String
    public var icon: ItemIcon?
    public var currentDirectoryPath: String?
    public var needsConfirmation: Bool
    /// Inline mode refresh interval in seconds (≥ 10); nil = no refresh.
    public var refreshSeconds: Int?
    public var arguments: [ArgumentSpec]
    public var description: String?

    public init(
        path: String,
        title: String,
        mode: Mode,
        packageName: String,
        icon: ItemIcon? = nil,
        currentDirectoryPath: String? = nil,
        needsConfirmation: Bool = false,
        refreshSeconds: Int? = nil,
        arguments: [ArgumentSpec] = [],
        description: String? = nil
    ) {
        self.path = path
        self.title = title
        self.mode = mode
        self.packageName = packageName
        self.icon = icon
        self.currentDirectoryPath = currentDirectoryPath
        self.needsConfirmation = needsConfirmation
        self.refreshSeconds = refreshSeconds
        self.arguments = arguments
        self.description = description
    }
}

/// Actions the Action Panel (⌘K) offers. Which ones an item gets: `ItemActions.actions(for:…)`.
public enum ItemActionID: String, CaseIterable, Sendable {
    case open
    case showInFinder
    case copyPath
    case copyBundleID
    case copyLink
    case copyName
    case copyResult
    case quitApplication
    case hideApplication
    case editScript
    case toggleFavorite
    case moveFavoriteUp
    case moveFavoriteDown
    case setHotkey
    case deleteHotkey
    case setAlias
    case deleteAlias
    case disableCommand
}
