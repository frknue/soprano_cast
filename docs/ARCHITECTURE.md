# Soprano Cast architecture

Soprano Cast is a keyboard launcher for macOS in the Soprano family: a copy of Raycast's
Root Search and its hotkeys (global hotkeys of every Raycast type on any command, aliases,
favorites, the Action Panel, window management, system commands, quicklinks, Raycast-format
script commands, an inline calculator) drawn in Soprano's "Mission Control" chrome.
Swift 6 + programmatic AppKit, SPM, macOS 14+, menu-bar app (no Dock icon). Behavior is
reimplemented from Raycast's manual (manual.raycast.com: Keyboard Shortcuts, Command
Aliases & Hotkeys, Window Management, Quicklinks) and the script-commands README; no
Raycast code is used.

## Toolchain

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
```

The `ld: warning: building for macOS-14.0 …` link warnings are expected.

## Identity

| What | Value |
|---|---|
| Product | Soprano Cast (`/Applications/Soprano Cast.app`) |
| Bundle id | `com.soprano.cast`; dev `com.soprano.cast.dev` (`Soprano Cast Dev.app`) |
| Targets | `SopranoCastCore` (library), `SopranoCast` (executable), `SopranoCastTests` |
| SPM resource bundle | `SopranoCast_SopranoCast.bundle` |
| Settings | `~/.config/soprano-cast/settings.json` (`$XDG_CONFIG_HOME/soprano-cast/` when set); `SOPRANO_CAST_CONFIG` overrides the path |
| App state | `UserDefaults` (injectable): usage records, search history; `UserDefaults.standard` `didRequestPermissions` (first-launch prompt) |
| CLI port | CFMessagePort `<bundle id>.cli` |
| Signing | Soprano's shared "Soprano Local Development" identity (keeps Accessibility across rebuilds) |

## Modules and ownership

| Path | Module | Contents |
|---|---|---|
| `Sources/SopranoCastCore/` | Core | Pure logic, Foundation + CoreGraphics only, no AppKit, everything `public`: items, keys and hotkeys (parsing, recorder, gesture detection, conflicts), settings, search and ranking, calculator, quicklink templates, script metadata, window layout math, launcher key routing and list navigation, CLI messages. |
| `Sources/SopranoCastCore/Vendored/JSONCText.swift` | — | Copied from Soprano by `scripts/sync-soprano-chrome.sh`. Never edit. |
| `Sources/SopranoCast/Vendored/` | — | Soprano chrome (RetroChrome, Theme, NSColor+Hex, AppVersion, FileSystemWatcher). Never edit. |
| `Sources/SopranoCast/System/` | System | App catalog, icons, app/quicklink/system/script execution, window manager, hotkey center + Hyper key. |
| `Sources/SopranoCast/Launcher/` | Launcher | `LauncherController` and `LauncherWindow` (panel, search bar, list, footer, overlays, HUD). |
| `Sources/SopranoCast/App/`, `Shell/` | Shell | `main.swift`, app delegate (composition root), menu bar, login item, settings/theme centers, app state store, permissions window, CLI. |
| `Sources/SopranoCast/Fixtures/` | Fixtures | Fake catalog/runner/hotkeys and the `snapshot` harness. |

### Contract files (shared interfaces; change only together with every consumer)

- `Core/Items.swift` — `ItemID`, `ItemKind`, `ItemIcon`, `BuiltinGlyph`, `ArgumentSpec`, `CastItem`, `SystemCommand`, `WindowCommand`, `CastCommand`, `Quicklink`, `ScriptCommand`, `ItemActionID`.
- `Core/Keys.swift` — `ModifierSet`, `ModifierSides`, `NamedKey`, `KeySpec`, `KeyEvent`, `ModifierKey`, `KeySide`, `SidedModifier`, `HotkeyCombo`, `HotkeySpec`, `HotkeyTarget`, `HotkeyBinding`.
- `Core/Settings.swift` — every setting with Raycast's defaults, `ConfigIssue`, `SettingsResolution`.
- `Core/Launcher.swift` — `SectionKind`, `RankedItem`, `ResultSection`, `ItemAction`, `LauncherContext`, `LauncherCommand`, `RecorderUpdate`, `RunOutcome`, `CalculatorResult`, `UsageRecord`.
- `Core/CLIProtocol.swift`, `Core/Geometry.swift` (Quartz ↔ AppKit).
- `System/SystemContracts.swift` — `ItemSource`, `IconProviding`, `ItemRunning`, `HotkeyRegistering`, `HotkeyFailure`, `WindowManaging`.
- `Launcher/LauncherContracts.swift` — view models, `LauncherPresenting`, `SettingsEdit`, `LauncherEnvironment`.

(`Core/` = `Sources/SopranoCastCore/`; `System/`, `Launcher/`, `App/`, `Shell/`, `Fixtures/` =
`Sources/SopranoCast/…`; tests in `Tests/SopranoCastTests/`.)

### File ownership

| Owner | Files |
|---|---|
| Infra | `Package.swift`, `.gitignore`, `LICENSE`, `Support/*`, `scripts/*`, `Sources/SopranoCast/Resources/`, both `Vendored/` dirs, `App/SopranoResources.swift` |
| Core keys | `Core/KeyParsing.swift`, `Core/HotkeyParsing.swift`, `Core/HotkeyRecorder.swift`, `Core/ModifierGestureDetector.swift`, `Core/HotkeyConflicts.swift`; tests `KeyParsingTests`, `HotkeyParsingTests`, `HotkeyRecorderTests`, `ModifierGestureDetectorTests`, `HotkeyConflictsTests` |
| Core settings | `Core/SettingsResolver.swift`, `Core/SettingsTemplate.swift`, `Core/SettingsEditor.swift`; tests `SettingsResolverTests`, `SettingsTemplateTests`, `SettingsEditorTests` |
| Core search | `Core/SearchMatcher.swift`, `Core/Ranker.swift`, `Core/Frecency.swift`, `Core/SearchHistory.swift`, `Core/Calculator.swift`; tests `SearchMatcherTests`, `RankerTests`, `FrecencyTests`, `SearchHistoryTests`, `CalculatorTests` |
| Core commands | `Core/BuiltinItems.swift`, `Core/ItemActions.swift`, `Core/QuicklinkTemplate.swift`, `Core/ScriptMetadataParser.swift`, `Core/ScriptOutput.swift`, `Core/WindowLayout.swift`; tests `BuiltinItemsTests`, `ItemActionsTests`, `QuicklinkTemplateTests`, `ScriptMetadataParserTests`, `ScriptOutputTests`, `WindowLayoutTests` |
| Core launcher | `Core/LauncherKeyRouter.swift`, `Core/ResultNavigator.swift`; tests `LauncherKeyRouterTests`, `ResultNavigatorTests` |
| System apps | `System/LiveAppCatalog.swift`, `System/AppActions.swift`, `System/QuicklinkOpener.swift`, `System/LiveIconProvider.swift`; tests `AppCatalogScanTests` |
| System run | `System/SystemCommandRunner.swift`, `System/ScriptCatalog.swift`, `System/ScriptRunner.swift`, `System/LiveItemRunner.swift`; tests `ScriptRunnerTests` |
| System windows | `System/LiveWindowManager.swift`, `System/AXWindow.swift`; tests `WindowDisplayTests` |
| System hotkeys | `System/HotkeyCenter.swift`, `System/CarbonHotkeys.swift`, `System/ModifierTap.swift`, `System/KeyboardLayout.swift`, `System/HyperKeyController.swift`, `System/KeyEventConversion.swift`; tests `KeyboardLayoutTests`, `KeyEventConversionTests` |
| Launcher views | `Launcher/LauncherWindow.swift`, `Launcher/LauncherPanel.swift`, `Launcher/SearchBarView.swift`, `Launcher/ResultListView.swift`, `Launcher/FooterView.swift`, `Launcher/OverlayViews.swift`, `Launcher/HUDWindow.swift`; tests `LauncherWindowTests` |
| Launcher controller | `Launcher/LauncherController.swift`, `Launcher/LauncherModelBuilder.swift`; tests `LauncherControllerTests`, `LauncherModelBuilderTests`, `LauncherTestSupport` |
| Shell | `main.swift`, `App/AppDelegate.swift`, `App/MenuBarController.swift`, `App/LoginItem.swift`, `App/CLIServer.swift`, `App/CLIClient.swift`, `Shell/SettingsFile.swift`, `Shell/SettingsCenter.swift`, `Shell/ThemeCenter.swift`, `Shell/AppStateStore.swift`, `Shell/Permissions.swift`, `Shell/PermissionsWindowController.swift`; tests `SettingsCenterTests`, `AppStateStoreTests`, `CLIRoundTripTests`, `PermissionsWindowTests` |
| Fixtures | `Fixtures/FixtureCatalog.swift`, `Fixtures/FixtureIcons.swift`, `Fixtures/FixtureRunner.swift`, `Fixtures/FixtureHotkeys.swift`, `Fixtures/FixturePresenterSupport.swift`, `Fixtures/SnapshotCommand.swift`; tests `FixtureCatalogTests`, `SnapshotCommandTests` |

## Core APIs

Signatures are binding: other modules call them exactly like this.

### Keys (`KeyParsing.swift`)

```swift
extension ModifierSet {
    /// "cmd"/"command"/"⌘", "opt"/"option"/"alt"/"⌥", "ctrl"/"control"/"⌃", "shift"/"⇧",
    /// "fn"/"function", joined with "+", case-insensitive, spaces ignored; nil when empty/unknown.
    public init?(settingsText: String)
    public var settingsText: String { get }   // "ctrl+opt+shift+cmd+fn" order
    public var symbols: [String] { get }      // ["⌃","⌥","⇧","⌘","fn"] order
}
extension KeySpec {
    /// A NamedKey raw value (case-insensitive) or alias (enter→return, esc→escape,
    /// backspace→delete, spacebar→space); `key:<US name>` or `key:0x<hex>` (0…127, not a
    /// NamedKey code) → .physical; or one non-space character → .character(lowercased).
    public init?(settingsText: String)
    /// Round-trips: physical keys `key:<US name>`, else `key:0x<hex>`.
    public var settingsText: String { get }
    /// ⇥ ␣ ↩ ⎋ ⌫ ⌦ ← → ↑ ↓ ↖ ↘ ⇞ ⇟ F1…F20; characters and physical key names uppercased
    /// ("K", "'", "§"); unnamed physical keys "0x4b".
    public var symbol: String { get }
    /// Named: `keyCodes` contains `event.keyCode`. Physical: `event.keyCode` equals the code.
    /// Character: `event.baseCharacters` lowercased equals the character (so ⇧⌘1 matches
    /// "1", not "!"); false when nil. Modifiers are not compared.
    public func matches(_ event: KeyEvent) -> Bool
}
/// US-ANSI names of the printable keys by key code: a–z, 0–9, - = [ ] \ ; ' , . / ` and
/// § (0x0A, the ISO key above Tab).
public enum PhysicalKeyNames {
    public static func name(forKeyCode code: UInt16) -> String?
    public static func keyCode(forName name: String) -> UInt16?
}
```

`KeySpec` has three cases. `named` is a special key by position. `physical(UInt16)` is a
printable key by position, independent of the layout — Raycast's default for recorded
hotkeys, so `cmd+key:'` keeps working when the user switches from ABC to German (where the
same key types "ä"). `character` is a key equivalent: the key that types the character on
the current layout, re-resolved when the layout changes. `ModifierKey` also carries
`canonicalOrder` (⌃⌥⇧⌘fn), `settingsName`, `aliases`, `symbol`, `member`,
`physicalKey(on:)` and `physicalKeys`; `SidedModifier` has `init?(settingsText:)`,
`settingsText` and `keycap`.

`KeyEvent` carries `baseCharacters: String?` — the characters the key types with no
modifiers at all on the current layout (`NSEvent.characters(byApplyingModifiers: [])`),
default nil.

### Hotkey specs (`HotkeyParsing.swift`)

```swift
extension HotkeySpec {
    /// Grammar (case-insensitive, spaces ignored):
    ///   combo:   modifiers "+" key       "cmd+shift+k", "hyper+1", "ctrl+opt+left", "fn+a",
    ///                                    "cmd+key:'" (physical key)
    ///            key alone (F13–F20)     "f13"
    ///   taps:    modifiers only          "rcmd", "lopt", "cmd+opt", "fn"
    ///            (sided names "l"/"r" + any modifier name: lcmd rcmd lopt ralt lshift …;
    ///            plain = any side; fn has no sides)
    ///   double:  "double:" modifier      "double:cmd", "double:rshift"
    ///   both:    "both:" modifier        "both:cmd" (not fn)
    /// "hyper" sets `usesHyper` (combos only). nil for anything else, including a combo with
    /// no modifier whose key is not F13–F20. The key comes last ("cmd++" is ⌘ and the plus
    /// key); each modifier appears at most once; combos take plain (side-less) names only;
    /// "double:"/"both:" only count as a prefix of the whole text.
    public init?(settingsText: String)
    /// Canonical spelling: "hyper" first, then ctrl, opt, shift, cmd, fn, then the key.
    public var settingsText: String { get }
    /// Keycaps in ⌃⌥⇧⌘fn order: ["⇧","⌘","K"], ["✦","1"] (✦ = Hyper, first), ["R⌘"],
    /// ["⌘","⌘"] (double), ["L⌘","R⌘"] (both). The app draws a physical key as what the
    /// current layout types on it (`KeyboardLayout.keycaps(for:)`).
    public var keycaps: [String] { get }
    /// Shape names for messages: "⇧⌘K".
    public var displayString: String { get }
}
```

### Recorder (`HotkeyRecorder.swift`)

```swift
public struct HotkeyRecorder: Sendable {
    public init()
    public private(set) var recorded: HotkeySpec?
    public mutating func handle(_ event: KeyEvent) -> RecorderUpdate
    public static let doubleTapWindow: TimeInterval   // 0.35 s
}
```

Rules: a non-repeat keyDown of Escape / Return / Delete with no modifiers → `.cancelled` /
`.commit` / `.cleared`. Any other keyDown with at least one modifier, or of F13–F20 alone,
records `.combo` (named key when the key code is a `NamedKey`, else `.physical(keyCode)` —
Raycast's default, so ⌘1 saves as `cmd+key:1` and survives layout switches; ⌃⌥⇧⌘ all
held records `usesHyper: false` with all four — the recorder never invents "hyper"). A
keyDown without modifiers of any other key, a repeat and a keyUp → `.unchanged`.
flagsChanged while modifiers are held → `.pending(display:)` (sided keycaps like "R⌘"
when exactly one side is down); once a key went down during the hold, further
flagsChanged → `.unchanged` (the combo stays shown). When every modifier is up again and
no non-modifier key went down in between: one modifier tapped → `.modifierTap([its
side])`; several → `.modifierTap(set)` (sides as pressed); the same single modifier (same
side) tapped again with its press within `doubleTapWindow` of the previous release →
`.doubleTap`; left and right of one modifier (and nothing else) down at the same time →
`.bothSides`; both sides plus other modifiers → `.pending(display: [])`. Each `.recorded`
replaces `recorded`.

### Modifier gestures (`ModifierGestureDetector.swift`)

```swift
public struct ModifierGestureDetector: Sendable {
    /// Only `.modifierTap`, `.doubleTap`, `.bothSides` specs are watched; others ignored.
    public init(specs: [HotkeySpec])
    /// Feed every flagsChanged / keyDown (timestamps matter); returns the specs that fired.
    public mutating func handle(_ event: KeyEvent) -> [HotkeySpec]
    public static let maxTapDuration: TimeInterval   // 0.5 s
}
```

A tap fires on the release of its last modifier when exactly its modifiers went down
(`.any` matches either side), no other key went down, and press→release ≤
`maxTapDuration`. A double tap fires on the second clean tap when its press comes within
`HotkeyRecorder.doubleTapWindow` after the first release. Both-sides fires once when the
second side goes down and nothing else is held. A hold with both sides of a modifier never
fires a tap. Any non-modifier keyDown cancels the gesture in progress, including a pending
double tap. Duplicate specs are watched once.

### Conflicts (`HotkeyConflicts.swift`)

```swift
public struct HotkeyConflict: Equatable, Sendable {
    public var spec: HotkeySpec
    public var targets: [HotkeyTarget]
    /// "same" (identical after expanding Hyper) or "cannotCoexist" (⌥ tap vs ⌥⌥ double tap,
    /// any-side ⌘ tap vs both-sided ⌘).
    public var reason: Reason
    public enum Reason: Equatable, Sendable { case same, cannotCoexist }
}
public enum HotkeyConflicts {
    public static func conflicts(in bindings: [HotkeyBinding], hyperIncludesShift: Bool) -> [HotkeyConflict]
    /// The target already using `spec` (or one that cannot coexist with it), other than `except`.
    public static func owner(of spec: HotkeySpec, in bindings: [HotkeyBinding], except: HotkeyTarget?, hyperIncludesShift: Bool) -> HotkeyTarget?
}
```

Bindings of the same target never conflict. `conflicts` lists `.same` groups first, then
one `.cannotCoexist` per pair.

### Settings (`SettingsResolver.swift`, `SettingsTemplate.swift`, `SettingsEditor.swift`)

```swift
public enum SettingsResolver {
    /// JSONC → settings over the defaults; unknown keys and bad values warn (dotted paths),
    /// a non-object document gives settings == nil and one .error with its line.
    public static func resolve(text: String, knownThemeIDs: Set<String>) -> SettingsResolution
}
public enum SettingsTemplate {
    /// The commented settings.json written on first launch; resolves to `.defaults`, no issues.
    public static let text: String
}
public struct SettingsEditError: Error, Equatable { public let message: String; public let line: Int }
public enum SettingsEditor {
    /// Sets `value` (Bool, Int, Double, String, [Any], [String: Any], NSNull) at `path`,
    /// keeping comments and key order; creates missing intermediate objects (a whole
    /// document when the text is empty or only comments).
    public static func setting(_ value: Any, at path: [String], in text: String) throws -> String
    /// Unchanged text when the key is absent; removing the only member leaves `{}`.
    public static func removing(at path: [String], in text: String) throws -> String
}
```

settings.json (every key optional):

```jsonc
{
  "theme": "soprano",
  "launcher": {
    "hotkey": "cmd+space",          // null = none
    "screen": "withMouse",          // withMouse | withActiveWindow | primary
    "popToRootSeconds": 90,         // 0…3600
    "navigation": "emacs",          // emacs (⌃N/⌃P) | vim (⌃J/⌃K) | both
    "closeOnFocusLoss": true
  },
  "hotkeys": { "app:com.google.Chrome": "cmd+key:1", "window:leftHalf": "ctrl+opt+left" },
  "aliases": { "app:com.google.Chrome": "gc" },
  "favorites": ["app:com.google.Chrome"],
  "disabled": ["system:toggleHiddenFiles"],
  "fallbacks": ["cast:searchGoogle"],
  "quicklinks": [
    { "id": "github", "name": "GitHub Repo", "link": "https://github.com/{argument name=\"repo\"}", "openWith": "com.google.Chrome", "icon": "🐙" }
  ],
  "scriptDirectories": ["~/raycast-scripts"],
  "applicationDirectories": [],
  "hyperKey": { "trigger": null, "includeShift": true, "quickPress": "nothing" },
  "windowManagement": { "gap": 0, "halves": "stay" },   // stay | cycleSizes | moveToDisplay
  "app": { "startAtLogin": true, "showMenuBarIcon": true }
}
```

Rules: item ids must parse to a known `ItemKind` with a non-empty key (unknown prefix
warns, entry dropped; ids of items that don't exist right now are kept — apps get
installed later). Hotkeys parse with `HotkeySpec(settingsText:)` (invalid → warning,
dropped); `null` removes; `hyperKey` resolves first, then two entries with the same spec
(compared with Hyper expanded): the later (by sorted id) is dropped with a warning naming
both, and anything clashing with `launcher.hotkey` is dropped with a warning. Aliases are
trimmed and lowercased; empty ones and characters other than a–z, 0–9 and space drop the
alias with a warning; duplicate aliases warn on the later id (both kept). `favorites`,
`disabled`, `fallbacks`: repeated entries warn and are dropped; a non-array keeps the
default. Directory lists drop blank entries. Quicklink ids must match `[a-z0-9-]+` and be
unique (later duplicates dropped); `link` and `name` non-blank strings; a bad `openWith`
or `icon` is ignored, an empty one becomes nil; unknown keys inside a quicklink warn.
`hyperKey.quickPress` other than `nothing` requires `trigger: "capsLock"` (else warns,
`nothing`). Ranges clamp with a warning. Booleans only JSON booleans; integers only whole
numbers below 1e9. Warnings read `<dotted.path>: <value> is not …; kept/dropped …`;
errors: `settings.json must be a JSON object`, `settings.json could not be read: …`, or
the JSONC parse error, each with its line.

Known upstream issue: the vendored `JSONCText` `removing` of an object's last member
deletes from the previous member's comma, so a trailing comment on the line before (and
comment lines in between) is lost. The fix belongs in Soprano, then a re-sync.

### Search (`SearchMatcher.swift`, `Ranker.swift`, `Frecency.swift`, `SearchHistory.swift`, `Calculator.swift`)

```swift
public enum SearchMatcher {
    /// Fuzzy subsequence, case + diacritic insensitive; whitespace-separated terms must all
    /// match; consecutive and word-start characters score higher; ranges index `text`.
    public static func match(_ query: String, in text: String) -> SearchMatch?
}
public struct SearchMatch: Equatable, Sendable { public var score: Int; public var ranges: [Range<String.Index>] }

public enum Ranker {
    /// Root Search sections for `query` (trimmed). Empty query: `.favorites` (settings order,
    /// existing, not disabled) then `.suggestions` (top `maxSuggestions` by frecency,
    /// excluding favorites, only items used at least once). Otherwise: `.calculator` (when
    /// `calculator` is non-nil, one row: `ItemID.calculatorResult`, title = formatted answer,
    /// subtitle = expression, `.glyph(.calculator)`), `.results`, `.fallbacks`
    /// (settings.fallbacks that exist and aren't disabled). Empty sections are omitted; a
    /// repeated id keeps its first item.
    public static func sections(
        query: String, items: [CastItem], settings: CastSettings,
        usage: [ItemID: UsageRecord], now: Date, calculator: CalculatorResult?
    ) -> [ResultSection]
    public static let maxResults: Int       // 60
    public static let maxSuggestions: Int   // 6
}
public enum Frecency {
    /// Σ over uses of 100 (< 4 days), 70 (< 14), 50 (< 31), 30 (< 90), 10 (older).
    public static func score(_ record: UsageRecord, now: Date) -> Int
    /// Adds a use at `date` (newest first, at most 10 kept).
    public static func recording(_ date: Date, in record: UsageRecord?) -> UsageRecord
}
public struct SearchHistory: Equatable, Sendable {
    public init(entries: [String] = [])
    public private(set) var entries: [String]           // newest first, unique, max 50
    public mutating func record(_ query: String)        // ignores empty / whitespace
    /// ↑ at the top of the list: the next older entry (nil past the end); ↓: newer (nil = back to typing).
    public mutating func previous(currentQuery: String) -> String?
    public mutating func next() -> String?
    public mutating func resetCursor()
}
public enum Calculator {
    /// nil unless `text` is a full expression with at least one operator or function:
    /// + - − * / × ÷ ^ (right-associative), postfix % (÷ 100), parentheses, unary minus
    /// (alone it doesn't count: "-5" → nil), decimals with "." or the locale's decimal
    /// separator (".5", "5."), functions sqrt abs round floor ceil sin cos tan (radians) log
    /// (10) ln exp with parentheses, constants pi π e; names case-insensitive; no implicit
    /// multiplication; nesting ≤ 64. Division by zero, NaN and ∞ → nil. The answer is
    /// formatted `.decimal` (grouping separators, up to 10 fraction digits, never "-0").
    public static func evaluate(_ text: String, locale: Locale) -> CalculatorResult?
}
```

Ranking with a query, per non-disabled item: alias equal to the query → tier 3; alias
starting with the query → tier 2; else the best `SearchMatcher` match over title (full
weight), keywords and subtitle (half weight, integer) → tier 1; no match → excluded.
Match scores are capped at 999 (per character: 1, +5 consecutive, +8 word start, a
lowercase→uppercase change counts as a word start). Score = tier × 1_000_000 + match
score × 1_000 + `Frecency.score` + 50 for favorites. Ties: title
`localizedStandardCompare`, then id. `matchedAlias` set for tiers 2–3; `titleRanges` from
the title match.

### Commands (`BuiltinItems.swift`, `ItemActions.swift`, `QuicklinkTemplate.swift`, `ScriptMetadataParser.swift`, `ScriptOutput.swift`, `WindowLayout.swift`)

```swift
public enum BuiltinItems {
    /// Every SystemCommand, WindowCommand and CastCommand item plus one item per quicklink,
    /// with titles, subtitles ("System", "Window Management", "Soprano Cast", the quicklink's
    /// link), keywords (e.g. "fullscreen", "dark mode", "trash", "half"; window commands also
    /// "window"), icons (`.glyph`; quicklinks: one emoji → `.emoji`, "/…" or "~…" → `.file`,
    /// else `.glyph(.link)`), `needsConfirmation` (system commands), and arguments (search
    /// commands: one "Query"; quicklinks: `QuicklinkTemplate.arguments`).
    public static func items(settings: CastSettings) -> [CastItem]
}
public enum ItemActions {
    /// The Action Panel for an item, in this order (only those that apply, none repeated):
    /// primary (↵), secondary (⌘↵), showInFinder (apps, scripts), copyPath (apps, scripts) /
    /// copyLink (quicklinks), copyBundleID (apps with a bundle id) / copyName (everything
    /// else), quitApplication + hideApplication (running apps), editScript (scripts),
    /// toggleFavorite, moveFavoriteUp/Down (favorites not already first/last), setHotkey,
    /// deleteHotkey (when set), setAlias, deleteAlias (when set), disableCommand. The
    /// calculator row gets only its primary, "Copy Answer".
    public static func actions(for item: CastItem, isRunning: Bool, isFavorite: Bool,
                               canMoveFavoriteUp: Bool, canMoveFavoriteDown: Bool,
                               hasHotkey: Bool, hasAlias: Bool) -> [ItemAction]
    /// The Configure Command submenu: setHotkey, deleteHotkey (when set), setAlias, deleteAlias (when set).
    public static func configureActions(hasHotkey: Bool, hasAlias: Bool) -> [ItemAction]
    /// ↵ / ⌘↵ / ⌥↵ for an item. Primary: open ("Open Application", "Open Quicklink", "Run
    /// Script", "Run Command", calculator "Copy Answer"). Secondary: app showInFinder,
    /// quicklink copyLink, script editScript, else nil (calculator included). Tertiary: app
    /// copyPath, else nil. Their `shortcut` is ↵, ⌘↵ and ⌥↵.
    public static func primary(for item: CastItem) -> ItemAction
    public static func secondary(for item: CastItem) -> ItemAction?
    public static func tertiary(for item: CastItem) -> ItemAction?
    /// In-launcher shortcuts: open ⌘O, showInFinder ⇧⌘O, copyPath/copyLink ⇧⌘C,
    /// copyBundleID/copyName ⌥⌘C, editScript ⌘E, toggleFavorite ⌘F, moveFavoriteUp ⇧⌘↑,
    /// moveFavoriteDown ⇧⌘↓, disableCommand ⇧⌘D. Others have none (`copyResult` is listed
    /// by no item: the calculator's ↵ already copies).
    public static func shortcut(for action: ItemActionID) -> HotkeyCombo?
}
```

Action titles: "Show in Finder", "Copy Path", "Copy Bundle Identifier", "Copy Link", "Copy
Name", "Copy Answer", "Quit Application", "Hide Application", "Edit Script", "Add to
Favorites" / "Remove from Favorites", "Move Up in Favorites", "Move Down in Favorites",
"Set Hotkey…", "Remove Hotkey", "Set Alias…", "Remove Alias", "Disable Command".
Destructive (drawn in `danger`): Quit Application, Remove from Favorites, Remove Hotkey,
Remove Alias, Disable Command.

```swift
public struct PlaceholderContext: Sendable {
    public var clipboard: String; public var now: Date; public var uuid: String
    public init(clipboard: String, now: Date, uuid: String)
}
public enum QuicklinkTemplate {
    /// Arguments from `{argument name="x" default="y"}`, `{argument}` ("Query") and legacy
    /// `{Query}`/`{query}`, in order, deduplicated by name, at most 3; a `default` makes it optional.
    public static func arguments(in link: String) -> [ArgumentSpec]
    /// Substitutes arguments (empty → that placeholder's default, then the first
    /// occurrence's), {clipboard}, {date} (yyyy-MM-dd), {time} (HH:mm), {uuid}. Values are
    /// percent-encoded with the `encodeURIComponent` set (only A–Z a–z 0–9 - _ . ! ~ * ' ( )
    /// stay) when the link has a URL scheme, raw for file paths. "~" or a leading "~/"
    /// expands to `home`. Attributes take either quote and any order; unknown `{…}` stays
    /// literal; names beyond the first three expand to their default or "".
    public static func expand(_ link: String, arguments: [String], context: PlaceholderContext, home: String) -> String
}
public enum ScriptParseError: Error, Equatable, Sendable {
    case missingRequired(String)       // "schemaVersion", "title", "mode"
    case unsupportedSchema(String)
    case badValue(key: String, value: String)
}
public enum ScriptMetadataParser {
    /// `@raycast.<key> <value>` lines in `#`, `//` or `--` comments (first occurrence wins; no
    /// value = absent): schemaVersion (1), title, mode (case-insensitive),
    /// packageName (default: `directoryName`), icon (emoji → .emoji; https URL → .url; else a
    /// path relative to the script's folder → .file), iconDark (ignored), currentDirectoryPath,
    /// needsConfirmation (exactly true/false), refreshTime ("10s" "1m" "12h" "1d", minimum
    /// 10 s), argument1…3 (missing placeholder → "Argument N", missing type → text)
    /// (JSON: type text|password|dropdown, placeholder, optional, percentEncoded, data
    /// [{title,value}]), description. Files whose name contains ".template." are rejected by
    /// the caller.
    public static func parse(contents: String, path: String, directoryName: String) -> Result<ScriptCommand, ScriptParseError>
}
public enum ScriptOutput {
    public static func strippingANSI(_ text: String) -> String
    /// The last non-empty line, ANSI stripped.
    public static func lastLine(_ text: String) -> String?
}
public enum WindowLayout {
    /// The target frame (global Quartz coordinates) for `command` on a window at `frame` on a
    /// display whose visible frame is `visible`. Gap g: g at display edges and between
    /// regions. nil for toggleFullscreen, restore, previousDisplay, nextDisplay (the window
    /// manager handles those). `halves: .cycleSizes` cycles Left/Right Half ½ → ⅔ → ⅓ → ½
    /// when the window already is (±2 pt) the current step; `.moveToDisplay` is the window
    /// manager's (this returns the plain half). Frames are integral.
    public static func frame(for command: WindowCommand, window frame: CGRect, visible: CGRect, gap: CGFloat, halves: HalvesBehavior) -> CGRect?
    /// `frame` moved from `source` to `target` visible frames keeping its relative position
    /// (its center lands on the same relative point of `target`) and its aspect ratio
    /// (Raycast's "Keep Aspect Ratio"): the size scales by one factor, the smaller of the two
    /// display ratios when the target is smaller, further reduced until it fits `target`,
    /// never above 1. Clamped inside `target`; integral.
    public static func moved(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect
    /// Whether `frame` equals `expected` within `tolerance`.
    public static func matches(_ frame: CGRect, _ expected: CGRect, tolerance: CGFloat) -> Bool
}
```

Window rules: halves/thirds/fourths/quarters/sixths split the visible frame into equal
regions; maximize fills it (minus gaps); almostMaximize = 90 % of the visible frame,
centered (gap ignored); maximizeHeight / maximizeWidth keep the other axis;
reasonableSize = 60 % of each side capped at 1025 × 900, centered (gap ignored); center
keeps the size (clamped inside the gaps), centered in the visible frame; centerHalf = one
half column (with gaps) wide, full height, centered; moveUp/Down/Left/Right keep the size
(clamped) and touch that edge (with gap), centered along it (Raycast's "Center Window"
option); makeLarger/makeSmaller grow/shrink by 10 % of the visible size around the window
center, clamped inside the gaps, at least 200 × 150 (capped at that area).

### Launcher (`LauncherKeyRouter.swift`, `ResultNavigator.swift`)

```swift
public struct RouterInput: Equatable, Sendable {
    public var context: LauncherContext
    public var navigation: NavigationBindings
    public var selectionAtTop: Bool
    public var selectionAtBottom: Bool
    public var selectionHasArguments: Bool
    public init(context:navigation:selectionAtTop:selectionAtBottom:selectionHasArguments:)
}
public enum LauncherKeyRouter {
    /// The command for a keyDown, or nil to pass it to the focused text field (or to the
    /// recorder in `.hotkeyRecorder`, which gets every event). flagsChanged → nil.
    public static func command(for event: KeyEvent, input: RouterInput) -> LauncherCommand?
}
public enum ResultNavigator {
    /// The new flat selection for a move command over sections with these row counts:
    /// moveUp/moveDown step (no wrap); pageUp/pageDown jump `pageSize`; sectionUp/sectionDown
    /// go to the first row of the previous/next section (sectionUp inside a section goes to its
    /// first row first). nil when there are no rows; other commands return `selected`.
    public static func move(_ command: LauncherCommand, selected: Int?, rowCounts: [Int], pageSize: Int) -> Int?
}
```

Key map (Raycast's). Modifiers must match exactly; arrow keys ignore `.function` (macOS
sets it on them); auto-repeat only produces movement commands (holding ↵ never runs
twice). Every context but the recorder: ⌘W closeWindow, ⌘Esc popToRoot.
- **root**: ↑ moveUp (historyPrevious when `selectionAtTop`), ↓ moveDown (historyNext when
  `selectionAtBottom`), ⌃P/⌃N (emacs, both), ⌃K/⌃J (vim, both); ⌥↑/⌥↓ pageUp/pageDown;
  ⌘↑/⌘↓ sectionUp/sectionDown; ⇧⌘↑/⇧⌘↓ moveFavoriteUp/Down; ↵ runPrimary; ⌘↵ runSecondary;
  ⌥↵ runTertiary; ⌘K toggleActionPanel; ⇧⌘, configureCommand; ⌘, openSettings; ⌘F
  toggleFavorite; ⇧⌘D disableCommand; the other `ItemActions.shortcut` combos (⌘O, ⇧⌘O,
  ⇧⌘C, ⌥⌘C, ⌘E) → `runAction`; Tab nextArgument and ⇧Tab previousArgument when
  `selectionHasArguments` or an argument is focused (`.root(argumentFocused:)`); Esc back.
  Everything else (typing, ⌃F/⌃B, ⌘A/⌘C/⌘V, ←/→) → nil.
- **actionPanel**: ↑/↓ and the navigation bindings move; ↵ runPrimary (the selected
  action); ⌘↵ runSecondary; ⌘K toggleActionPanel; Esc back; action shortcuts (⌘F, ⇧⌘D,
  ⇧⌘↑/↓ included) → `runAction`; typing → nil (filter field). ⌥↑/⌥↓, ⌘↑/⌘↓ and ⇧⌘, → nil.
- **hotkeyRecorder**: always nil (⌘W and ⌘Esc are recorded like any combo).
- **aliasEditor**: ↵ runPrimary (save), Esc back, else nil.
- **output**: ↵ and Esc back, else nil (the text view handles ⌘C/⌘A).
- **confirmation**: ↵ runPrimary (confirm), Esc back, else nil.

## System APIs

```swift
@MainActor final class LiveAppCatalog: ItemSource { init(extraDirectories: [String]); func setExtraDirectories(_: [String]) }
@MainActor final class LiveIconProvider: IconProviding { init(theme: @escaping @MainActor () -> AppTheme) }
@MainActor enum AppActions {
    static func open(_ item: CastItem)            // app items: activate, reopen when windowless, or launch
    static func isRunning(_ item: CastItem) -> Bool
    static func quit(_ item: CastItem)
    static func hide(_ item: CastItem)
    static func bundleURL(for item: CastItem) -> URL?
}
@MainActor enum QuicklinkOpener {
    /// Expands the template and opens it (with `openWith` when set: bundle id, app name or path).
    static func open(_ quicklink: Quicklink, arguments: [String]) -> RunOutcome
    static func open(urlString: String, openWith: String?) -> RunOutcome
}
@MainActor final class SystemCommandRunner { init(); func run(_ command: SystemCommand) -> RunOutcome }
@MainActor final class ScriptCatalog: ItemSource {
    init(directories: [String], runner: ScriptRunner = ScriptRunner())
    func setDirectories(_: [String]); func reload(); func script(for id: ItemID) -> ScriptCommand?
    func recordInlineResult(_ execution: ScriptExecution, for path: String)
    static let maxInlineScripts: Int   // 10
}
@MainActor final class ScriptRunner {
    init()
    func run(_ script: ScriptCommand, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void)
    func execute(_ script: ScriptCommand, arguments: [String], completion: @escaping @MainActor (ScriptExecution) -> Void)
    nonisolated static func outcome(for script: ScriptCommand, execution: ScriptExecution) -> RunOutcome
}
struct ScriptExecution { var output: String; var status: Int32; var terminatedBySignal: Bool; var launchError: String? }
@MainActor final class LiveItemRunner: ItemRunning {
    init(windowManager: WindowManaging, scripts: ScriptCatalog, scriptRunner: ScriptRunner,
         systemCommands: SystemCommandRunner, settings: @escaping @MainActor () -> CastSettings,
         castCommand: @escaping @MainActor (CastCommand) -> RunOutcome)
}
@MainActor final class LiveWindowManager: WindowManaging { init() }
@MainActor final class HotkeyCenter: HotkeyRegistering { init() }
@MainActor final class HyperKeyController { init(); func apply(_ settings: HyperKeySettings) -> String? ; func remove() }
enum KeyEventConversion {   // main thread only (NSEvent reads the layout)
    static func keyEvent(from event: CGEvent, type: CGEventType) -> KeyEvent?
    static func keyEvent(from event: NSEvent) -> KeyEvent?
    static func modifiers(from flags: CGEventFlags) -> ModifierSet
    static func sides(from flags: CGEventFlags) -> ModifierSides
    /// Arrows, Home/End, Page Up/Down, Forward Delete, Help and F1–F20: macOS sets fn on
    /// them; it is stripped from their (non-flagsChanged) events.
    static let inherentFunctionKeyCodes: Set<UInt16>
}
enum KeyboardLayout {      // main thread only
    /// The key code that types `character` (lowercased) with no modifiers on the current
    /// layout (UCKeyTranslate over codes 0…127, lowest code wins), nil when none does.
    static func keyCode(for character: Character) -> UInt16?
    /// The character key code `keyCode` types with no modifiers on the current layout.
    static func character(for keyCode: UInt16) -> Character?
    /// A physical key shows what it types on the current layout, uppercased ("Ä" on German
    /// for `key:'`), else `KeySpec.symbol`; `keycaps(for:)` applies it to a combo's key.
    static func keycapSymbol(for key: KeySpec) -> String
    static func keycaps(for spec: HotkeySpec) -> [String]
}
```

Every `ItemSource` has `start()` / `stop()`; the app delegate starts the app catalog and
script catalog after building the controller (the controller never starts its sources).

- **Apps**: `NSMetadataQuery` for `kMDItemContentTypeTree == "com.apple.application-bundle"`
  scoped to the existing folders of /Applications, /System/Applications, ~/Applications,
  /System/Library/CoreServices/Applications and `extraDirectories` (recursive), merged on
  every update with a direct scan of those folders 3 levels deep (Spotlight can be off)
  plus /System/Library/CoreServices/Finder.app. Reads `Contents/Info.plist`,
  `WrappedBundle/Info.plist` (iOS apps) or a flat `Info.plist`. Skips apps nested inside
  other bundles (.app .appex .bundle .framework .kext .plugin .prefpane .systemextension
  .xpc) and `LSBackgroundOnly` apps. One item per bundle id (prefer /Applications, then
  /System/Applications, then the shortest path, then alphabetical); id `app:<bundle id>`
  (`app:<path>` without one); title = Finder display name without ".app"; subtitle =
  folder, ~-abbreviated; keywords = bundle name, executable name (empty, title-equal and
  repeated values dropped); icon `.file(path)`; sorted by title, then id.
- **Open app** (`AppActions.open`): running (preferring a `.regular` instance) → unhide
  (waiting 300 ms for a hidden app) and activate with `.activateAllWindows`; if it then has
  no on-screen layer-0 window on the current Space,
  `NSWorkspace.openApplication(at:configuration:)` so it reopens a window (a Dock click).
  Not running → launch. (The ⌘1 → Chrome hotkey runs exactly this.)
- **Icons**: image and PDF files drawn as themselves, other files' icons from
  `NSWorkspace.icon(forFile:)`, emoji drawn into an image, glyphs from SF Symbols tinted
  with the theme accent on a `bgRaised` tile, remote icons fetched once into
  `~/Library/Caches/com.soprano.cast/icons/` (the script glyph until loaded, and for the
  session after a failure); all cached per (icon, size, theme for glyphs).
- **System commands**: lockScreen = `SACLockScreenImmediate` (login.framework via dlsym),
  falling back to posting ⌃⌘Q (needs Accessibility); sleep = `pmset sleepnow`;
  sleepDisplays = `pmset displaysleepnow`; restart/shutDown/logOut = Apple events
  `aevt/rest`, `aevt/shut`, `aevt/rlgo` to loginwindow (no reply; `rrst` would only show
  the dialog); emptyTrash = `NSAppleScript` `tell application "Finder" to empty trash`
  (ignoring responses); ejectAllDisks = `NSWorkspace.unmountAndEjectDevice` for every
  ejectable or removable, non-hidden volume except "/"; toggleSystemAppearance =
  `NSAppleScript` to System Events `appearance preferences`; quitAllApplications =
  terminate every regular app except Finder and Soprano Cast; hideOtherApplications = hide
  every visible regular app except the frontmost and Soprano Cast; toggleHiddenFiles =
  `defaults write com.apple.finder AppleShowAllFiles -bool …`, quit Finder (≤ 5 s) and
  reopen it in the background. Each returns `.hud("<title>")` or `.toast(error, isError:
  true)`: "Couldn't lock the screen", "No disks to eject", "Couldn't eject <names>",
  "Soprano Cast needs Automation access (System Settings › Privacy & Security ›
  Automation)" (-1743), "The Apple event failed". Only the Finder and System Events
  scripts need Automation; `Info.plist` `NSAppleEventsUsageDescription`: "Soprano Cast runs
  system commands such as Empty Trash and Toggle System Appearance."
- **Scripts**: `ScriptCatalog` scans each directory (and one level of subfolders, not
  entering bundles; hidden files skipped) for regular files without ".template." whose
  metadata parses; the default package name is the subfolder's name for scripts in a
  subfolder; watches the trees with the vendored `FileSystemWatcher` (rescan after 400 ms;
  watcher rescans don't rerun inline scripts, `reload()` does); item id `script:<path>`,
  subtitle = package name, keywords = description, icon from metadata or
  `.glyph(.script)`; sorted by title, then path. Inline-mode scripts (first
  `maxInlineScripts`) run on load, on reload and every `refreshSeconds` when set (a run
  still going is skipped) and show their last output line (or launch error) as the
  subtitle. `ScriptRunner` runs the file directly when executable, else via its shebang
  interpreter with its arguments; arguments are positional; cwd = `currentDirectoryPath`
  (~ expanded, relative to the script's folder) or the script's folder; PATH =
  /opt/homebrew/bin:/usr/local/bin: + inherited (or /usr/bin:/bin:/usr/sbin:/sbin);
  stdout and stderr share one pipe. Outcome by mode: silent → `.hud(lastLine ?? title)`,
  compact and inline → `.toast(lastLine ?? title)` (inline also refreshes the subtitle),
  fullOutput → `.output(title, output ANSI-stripped)`; a non-zero exit or signal →
  `.toast(lastLine ?? "Script failed", isError: true)` (fullOutput: `.output(…, isError:
  true)`); launch failures "Script not found: <path>" / "Script is not executable and has
  no #! line".
- **LiveItemRunner**: application → `AppActions.open`; systemCommand →
  `SystemCommandRunner`; windowCommand → `WindowManaging.perform` (`.hud(message)` when it
  returns one, else `.done(closeLauncher: true)`); quicklink → `QuicklinkOpener`; script →
  `ScriptRunner` (inline results also update the catalog); castCommand
  searchGoogle/searchDuckDuckGo → open `https://www.google.com/search?q=` /
  `https://duckduckgo.com/?q=` with the trimmed, encoded query, the rest → `castCommand`
  closure; calculator → copy the answer, `.hud("Copied")`. Copy actions write the
  pasteboard and return `.hud("Copied")`; Copy Link copies the quicklink's `link` template
  as written; Copy Name copies the title. Edit Script opens the script in its default app,
  or the default text editor when that is a terminal (Terminal, iTerm2, Ghostty, Warp,
  WezTerm, kitty, Alacritty). Errors: "Script not found", "Nothing to show in Finder", "No
  path to copy", "No bundle identifier", "Quicklink not found", "Not a script command",
  "Unknown command <id>".
- **Quicklink opener**: "Invalid link: <text>", "No such file: <path>" (file links must
  exist), "Can't find <openWith>". `openWith`: "/…" or "~…" is a path that must exist,
  else a bundle id, else an app name (".app" optional) in /Applications(/Utilities),
  /System/Applications(/Utilities), ~/Applications, /System/Library/CoreServices/Applications,
  /System/Library/CoreServices.
- **Window manager**: AX focused window of the frontmost app (position/size are Quartz; AX
  calls time out after 0.5 s); the display holding most of the window, else the nearest
  (NSScreen frames converted with `Geometry`); `WindowLayout.frame`; set position, size,
  then position again (AX applies size within the current display bounds); remembers the
  frame before each command that changed it (> 1 pt) per CGWindowID
  (`_AXUIElementGetWindow` via dlsym) for `restore`; toggleFullscreen flips `AXFullScreen`
  when settable; previous/nextDisplay move with `WindowLayout.moved` (aspect ratio kept)
  over displays sorted by left, then top edge, wrapping around (one display: nothing);
  halves `.moveToDisplay`: Left Half on a window already (±2 pt) the left half moves it to
  the right half of the display to the left (and mirrored); on the outermost display it
  stays. Messages: "Window Management needs Accessibility", "No focused window", "This
  window can't go full screen", "Nothing to restore", "This window can't be resized", "This
  window can't be moved".
- **Hotkey center**: combos without fn → Carbon `RegisterEventHotKey` (works without
  Accessibility; fires even while the launcher is key). Named and physical keys register
  their key code as is; character keys resolve through `KeyboardLayout.keyCode(for:)` and
  every registration is redone when the input source changes
  (`com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged`) while not suspended.
  Modifier-only specs (taps, double taps, both sides) and fn combos → a session CGEventTap
  on the main run loop for keyDown/keyUp/flagsChanged, listen-only unless fn combos are
  bound (an fn combo swallows its keyDown, repeats and keyUp), re-enabled after a timeout,
  feeding `ModifierGestureDetector`; needs Accessibility. fn is stripped from arrow and
  F-key events (`KeyEventConversion.inherentFunctionKeyCodes`), so fn+arrow / fn+F-key
  hotkeys never fire. Failure reasons (`HotkeyFailure`, settings order): "no key types <c>
  on this layout", "already registered", "not a valid hotkey", "couldn't register (error
  <n>)", "used by macOS" (matches an enabled macOS shortcut; still registered), "needs
  Accessibility", "event tap unavailable". Registration is tried while suspended too, then
  undone, so failures stay current. `suspend()` unregisters every Carbon hotkey and mutes
  the tap (the recorder must receive ⌘1 itself); `resume()` re-registers.
- **Hyper key**: `hidutil property --set` adds a mapping from the trigger (Caps Lock
  0x700000039, right ⌘ 0x7000000E7, right ⌥ 0x7000000E6, right ⌃ 0x7000000E4, right ⇧
  0x7000000E5; `f18` needs none) to F18 (0x70000006D) to the user's existing
  `UserKeyMapping` (stale entries from a crashed run dropped); an active keyDown/keyUp
  event tap swallows F18, holds a "hyper down" flag while it is down and ORs ⌃⌥⇧⌘ (⌃⌥⌘
  without Shift) into every key event meanwhile, so Carbon hotkeys registered with those
  modifiers fire; F18 released with no non-repeat keyDown in between → `quickPress`
  (capsLock trigger only: toggle Caps Lock via `IOHIDSetModifierLockState`, or post
  Escape). `remove()` restores the original mapping (also on quit; a nil trigger removes).
  Errors (everything undone): "Hyper Key needs Accessibility", "Hyper Key couldn't start
  its event tap", "Hyper Key: <hidutil error>".

## Launcher

```swift
@MainActor final class LauncherWindow: LauncherPresenting { init(); static var offscreen: Bool }

@MainActor final class LauncherController {
    init(sources: [ItemSource], icons: IconProviding, runner: ItemRunning, presenter: LauncherPresenting,
         hotkeys: HotkeyRegistering, environment: LauncherEnvironment)
    var isVisible: Bool { get }
    /// Every item Root Search can list right now (sources + `BuiltinItems`), for the CLI.
    var allItems: [CastItem] { get }
    func toggle()
    func show()
    func hide()
    /// A hotkey or the CLI: runs the item without showing the launcher. Unknown id → HUD
    /// "No command <id>". An item with required arguments missing opens the launcher pinned
    /// on it (only that row, under "results", until the query changes) with the first
    /// missing argument focused; one that needs confirmation opens pinned on its confirmation.
    func run(itemID: ItemID, arguments: [String])
    func settingsDidChange()
    /// For the harness and tests: the current state.
    var state: LauncherStateSnapshot { get }
}
struct LauncherStateSnapshot: Equatable {   // defined by the controller
    var query: String; var selectedID: ItemID?; var rowIDs: [ItemID]
    /// "none", "actionPanel", "configureCommand", "recorder", "aliasEditor", "output", "confirmation"
    var overlay: String
    var argumentValues: [String]; var footerToast: String?
}
struct LauncherToast: Equatable { var text: String; var isError: Bool }   // LauncherModelBuilder.swift
enum LauncherModelBuilder {
    static func model(theme:query:sections:selectedIndex:arguments:argumentValues:focus:toast:overlay:settings:icon:keycaps:) -> LauncherViewModel
    static func fallbacksTitle(query: String) -> String   // use “<query>” with…
}
```

Controller behavior:
- Builds `allItems` from its sources plus `BuiltinItems.items(settings:)`, refreshed on
  `onChange` and `settingsDidChange`. It only sets the sources' `onChange`; it never
  starts them (the app delegate does). Ranks with `Ranker.sections` on every query change
  (calculator from `Calculator.evaluate(query, locale: .current)`); selection resets to the
  first row on a query change.
- Keys: `presenter.onKeyEvent` → in `.hotkeyRecorder` every event goes to `HotkeyRecorder`;
  else `LauncherKeyRouter.command(for:input:)` → execute → true; nil → false.
- **runPrimary**: the selected row's primary action. An item with required arguments whose
  fields are empty focuses the first empty field instead (a toast "Fill in <argument
  name>" when already focused). `needsConfirmation` → the confirmation overlay first.
  Running records usage (`Frecency.recording`, every run but the calculator's, hotkey and
  CLI runs included) and, for runs from Root Search, the query in `SearchHistory`, then
  presents the `RunOutcome`: `.done(close)` closes when asked; `.hud` closes and shows the
  HUD; both close-after-run cases also pop to root (Raycast starts the next search fresh);
  `.toast` shows it in the footer for 3 s (a HUD while hidden); `.output` opens the output
  overlay (showing the launcher if needed). Fallback rows run their item with the query as
  the first argument.
- **runSecondary/runTertiary/runAction** → `ItemActions` lookups → `runner.perform` or the
  settings actions below; runner actions record neither usage nor history. Action Panel:
  heading = the item title; lists `ItemActions.actions` for the selection, filtered by its
  text (`SearchMatcher`; "no results" when nothing matches), ↵ runs the selected one;
  Configure Command (heading "Configure Command") opens `configureActions` in the same
  panel. Favorites, disable and configure ignore the calculator row.
- **Settings actions** (all through `environment.editSettings`; the settings center reloads
  and calls `settingsDidChange`): toggleFavorite appends/removes in `favorites`;
  moveFavoriteUp/Down swaps; disableCommand adds to `disabled` (written sorted; toast
  "Disabled <title>"); setHotkey opens the recorder overlay (calls `hotkeys.suspend()`;
  shows the current hotkey, "recording…" with none; every `.recorded` shows keycaps and the
  owner from `HotkeyConflicts.owner` in red ("Used by <title>", or the raw id when the item
  is gone); the launcher's own hotkey shows "Used by Soprano Cast", gets no countdown and
  can't be saved; a recorded spec starts a 1.5 s countdown (100 ms ticks) that saves
  `hotkeys.<id>`, overwriting a conflicting owner by removing its entry; `.commit` saves now
  (closes when nothing was recorded); `.cleared` removes and closes; `.cancelled` closes;
  `hotkeys.resume()` on leaving); deleteHotkey removes; setAlias opens the alias editor
  (prefilled, lowercased as typed; other characters than a–z, 0–9, space show "Use only
  a–z, 0–9 and spaces" and block ↵), ↵ saves the trimmed `aliases.<id>` (empty removes);
  deleteAlias removes. Write errors toast "settings.json line <n>: <message>" or "Couldn't
  edit settings.json".
- **back** (Esc): closes the topmost overlay; with none, closes the window. **popToRoot**:
  clears query, arguments, overlays, selection. **closeWindow** hides. `hide()` drops
  overlays and toasts and resets the history cursor; the query, selection and arguments
  stay. Reopening after more than `popToRootSeconds` since hiding (always, at 0) pops to
  root first.
- **History**: ↑ on the first row (or empty list) puts the next older history query (the
  newest that differs from the field first) into the field; ↓ on the last row the newer
  one, past the newest the query typed before browsing; typing resets the cursor.
- Arguments: the selected item's `arguments` become argument fields in the search bar
  (values kept per item while the selection doesn't change); Tab/⇧Tab cycle focus query →
  args → query; typing an alias + space, when that alias belongs to a listed non-fallback
  row with arguments, selects it and focuses its first argument (the space isn't typed).
- `run(itemID:)` (hotkeys): runs without showing; HUDs show on the launcher's display while
  it is visible, else `environment.screenFrame(settings.launcher.screen)`. The `.launcher`
  target is the app delegate's (`toggle()`).
- Shows on `environment.screenFrame(settings.launcher.screen)`; `onResignKey` hides when
  `closeOnFocusLoss`. Mouse: a click selects a row, a double click runs it, clicking an
  action runs it.
- Model: placeholder "Search for apps and commands…"; section headers "calculator",
  "favorites", "suggestions", "results" and `use “<query>” with…` for fallbacks; row
  accessory = `ItemKind.label` ("Application", "Command" for system, window and Soprano
  Cast commands, "Quicklink", "Script Command"; calculator: the expression and no
  subtitle; scripts: their package name, no subtitle); fallback rows show `“<query>”` as
  the subtitle and no argument fields; alias badge; hotkey keycaps
  (`KeyboardLayout.keycaps(for:)`); footer primary title from `ItemActions.primary` (only
  with a selection); empty text "No results" with a query, "Type to search apps and
  commands" without.

## Shell

- `main.swift`: before `NSApplication`, `snapshot` → `SnapshotCommand.run(arguments:)`
  (arguments after it); `toggle`, `open`, `list`, `help`, `--help` →
  `CLIClient.run(arguments:)` (command word included); both exit. Anything else starts
  the GUI with `.accessory` policy and `AppDelegate`.
- `AppDelegate` (composition root): forces `.darkAqua`, registers the bundled font;
  single-instance guard (a second instance terminates); `SettingsCenter.shared.start()`;
  `ThemeCenter.shared.start()`; `LiveAppCatalog`, `ScriptCatalog` (sharing the
  `ScriptRunner`), `LiveIconProvider`, `LiveWindowManager`, `SystemCommandRunner`,
  `LiveItemRunner` (cast commands: openSettings → `SettingsCenter.openInEditor()`,
  reloadScripts → HUD "Reloaded script directories", quit), `HotkeyCenter`,
  `HyperKeyController`, `LauncherWindow`, `LauncherController` with an environment over
  `SettingsCenter`, `ThemeCenter`, `AppStateStore` (UserDefaults) and
  `DispatchQueue.main.asyncAfter`; then starts the app and script catalogs.
  `hotkeys.onTrigger` → `.launcher` → `toggle()`, `.item(id)` → `run(itemID:arguments:
  [])`. At start (forced) and on settings changes: the Hyper key is re-applied when
  `hyperKey` changed, and `hotkeys.setBindings(settings.hotkeyBindings, hyperKey:)` runs
  when the bindings or the Hyper key changed; failures are logged and shown in the menu.
  While a hotkey or the Hyper key failed and Accessibility is missing, a 1 s poll re-applies
  everything once it is granted. Settings changes also update the catalogs' folders, the
  controller, the menu and (when `startAtLogin` changed) `LoginItem.sync`. On quit: Hyper
  key removed; the CLI server, the poll, the catalogs and the settings watcher stopped.
  `MenuBarController`; `CLIServer`. First launch (once ever, `didRequestPermissions` in
  `UserDefaults.standard`): when Accessibility is missing, macOS's prompt plus the
  permissions window; later launches never open it themselves. Reopen (Spotlight/Finder)
  → `toggle()`.
- `SettingsFile` / `SettingsCenter` / `ThemeCenter`: Soprano Tab's
  (`~/git/private/soprano-tab/Sources/SopranoTab/Shell/`) with Cast names: path
  `SOPRANO_CAST_CONFIG` > `$XDG_CONFIG_HOME/soprano-cast/settings.json` >
  `~/.config/soprano-cast/settings.json`; writes follow symlinks and are atomic; 120 ms
  debounce. `SettingsCenter` gains `edit(_ edit: SettingsEdit) throws` (via
  `SettingsEditor`, starting from the template when the file is missing) and
  `openInEditor()` (TextEdit when nothing opens JSON); an unreadable file is one error
  "Could not read <path>: …" and the last good settings stay. `ThemeCenter` follows
  Soprano's settings (`SOPRANO_CONFIG` > `$XDG_CONFIG_HOME/soprano/` > `~/.config/soprano/`).
- `AppStateStore(defaults: UserDefaults = .standard)`: usage records and search history as
  JSON data under `castUsage` / `castHistory` (unreadable data → empty).
- `MenuBarController(controller:settings:hotkeyProblems:openPermissions:)`: status item (18 pt
  programmatic template icon: a square with a slanted beam, tooltip "Soprano Cast"), menu:
  "Open Soprano Cast" (`show()`; the launcher hotkey as key equivalent, or appended as
  keycaps after two spaces for modifier gestures, fn combos and physical keys the layout
  types nothing with), "Settings…" (⌘,), a disabled "settings.json: N warning(s)" line
  (errors count; tooltip `line N: <message>` per issue), a disabled "N hotkey(s) need(s)
  attention" line (failures plus a failed Hyper key; tooltip `<shape> <title>: <reason>`,
  `Hyper key: <error>`), "Permissions…", "Launch at Login" (checkmark; writes
  `app.startAtLogin`), "About Soprano Cast" (version `AppVersion.current`), "Quit Soprano
  Cast" (⌘Q). The status item is removed while `showMenuBarIcon` is false.
- `Permissions` + `PermissionsWindowController(status:theme:)`: Soprano Tab's, window
  "Soprano Cast Permissions", heading "permissions", one row: "accessibility" — "window
  management, modifier-only hotkeys and the Hyper key", "Open System Settings" (prominent
  while missing); polls every 1 s while visible.
- `CLIServer(controller: CLIControlling, settings:)` (`CLIControlling`: `allItems`,
  `toggle()`, `run(itemID:arguments:)`; `start()`/`stop()`; port `<bundle id>.cli`, falling
  back to `com.soprano.cast.cli` unbundled) / `CLIClient`. Usage, verbatim:

  ```text
  Usage: SopranoCast <command>

    toggle                          Open or close the launcher
    open <item-id> [argument…]      Run an item as its hotkey would, e.g. open app:com.google.Chrome
                                    or open cast:searchGoogle "swift testing"
    list                            List every item as JSON, sorted by title
    help                            Show this help
  ```

  `toggle` and `list` take no arguments; `open` needs an id; `help`/`--help` print the
  usage to stdout, exit 0. Malformed arguments: usage on stderr, exit 2. Errors on stderr,
  exit 1: "Soprano Cast is not running.", "Soprano Cast did not answer." (2 s timeouts),
  "Could not encode the request.", "Soprano Cast sent an unreadable response.", "Could not
  encode the response.", "The request failed.", and from the server "Bad request.",
  "Unknown item id <id>; ids look like app:com.google.Chrome", "No item <id>" (disabled
  items still run). `list` prints a pretty JSON array (sorted keys, unescaped slashes) of
  `CLIItem` {id, title, kind (`ItemKind` raw value), subtitle, hotkey (settings spelling),
  alias, favorite, disabled}, sorted by title, then id.

## Fixtures and the snapshot harness

`FixtureCatalog` (an `ItemSource` with 14 apps — Google Chrome, Safari, Soprano, Soprano
Git, Soprano Tab, Slack, Mail, Notes, Music, Finder, System Settings, Xcode, Aside,
WhatsApp; Chrome, Soprano, Slack and Finder running — plus 3 script commands: "Keep Awake"
silent, "Search Issues" compact with a required "query" argument, "Disk Usage"
fullOutput), `FixtureIcons` (square letter tiles, glyph drawings, emoji tiles),
`FixtureRunner` (records `run <id> "<arg>"` / `perform <action> <id>`, returns scripted
outcomes), `FixtureHotkeys` (records "setBindings N", "suspend", "resume"). Fixed `now`
(2026-10-19 12:00 UTC), usage (Chrome, Soprano, Slack used) and history ("slack",
"chrome", "left half").

`SopranoCast snapshot` builds the real `LauncherController` + `LauncherWindow` on fixtures
offscreen (no Dock icon, no state; settings default to `SettingsTemplate.text`, the
visible frame is the screen minus a 33 pt menu bar), shows the launcher, types `--query`
through `onQueryChange`, replays `--keys` through `onKeyEvent` (keys the launcher doesn't
consume type into the focused field; replay stops once the launcher closes), and writes
`renderSnapshot` at 2× over a backdrop. Usage, verbatim:

```text
usage: SopranoCast snapshot --out <png> [--query "<text>"] [--keys "<token> …"]
                            [--settings <jsonc>] [--screen 1512x982] [--theme <id>]
                            [--report <json>]
  --keys tokens, separated by spaces, replayed after --query:
    named keys   return enter esc escape tab space delete backspace forwardDelete
                 up down left right home end pageUp pageDown f1 … f20
    characters   one character types it when the launcher doesn't use it
                 ("A" = shift+a, "!" = shift+1; US keyboard)
    key:<name>   a printable key by position: key:' key:z key:0x27 (cmd+key:')
    modifiers    cmd shift opt ctrl fn joined with "+" before a key:
                 cmd+k cmd+return opt+return shift+tab shift+cmd+, cmd+f cmd+esc ctrl+n
    rec:<hotkey> the key events that record a settings.json hotkey in the recorder:
                 rec:cmd+1 rec:hyper+k rec:rcmd rec:cmd+opt rec:double:cmd rec:both:shift
    wait         lets 2000 ms pass (the recorder's countdown saves); wait:<ms> any span.
                 Without it time stands still: scheduled work (countdowns, toast
                 timeouts) never runs.
```

`--report` writes JSON (sorted keys, explicit nulls): `query`, `rows` (ids), `selected`,
`overlay`, `runs` (`FixtureRunner` log), `edits` (`set hotkeys.<id> = "…"`, `remove …`),
`footerToast`. Option errors print "snapshot: <error>" plus the usage and exit 2; render
failures exit 1; success prints the PNG path.

## Visual design

Vendored chrome only: `ThemeColors` tokens (+ `bgSelected`, `bgSelectedStrong`,
`railMuted`), `RetroFont.display(11 | 22)` for labels (small caps; never uppercase by hand),
`RetroFont.body(size)` for text, square corners, `RetroLamp` the only round chrome,
`RetroRuleView`, `RetroStripeView`. Appearance forced to `.darkAqua`.

- **Panel** 750 × 474, `bgBase` at 0.98, 1 pt `borderStrong`, shadow; borderless,
  non-activating `NSPanel` that becomes key (text input without activating the app), level
  `.modalPanel`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`.
- **Search bar** 56 high: query field body 18 `textPrimary`, placeholder `textMuted`;
  argument fields inline after the text (bordered boxes, body 14, 150 wide, dropdowns as
  pop-up menus), the focused one framed in `accent`; `borderSubtle` hairline below.
- **List**: section headers display 11 `textMuted` ("favorites", "results") with a rule;
  rows 40 high: 24 pt icon, title body 14 (matched characters `accent`), subtitle body 12
  `textMuted`, alias badge (display 11 chip, `bgRaised`, `borderSubtle`), trailing accessory
  body 12 `textMuted`; the selected row: `bgSelectedStrong` + 2 pt `accent` leading rail and
  its hotkey keycaps before the accessory. Scrolls to keep the selection visible.
- **Footer** 40 high, `bgPanel`, hairline on top: left a small `RetroStripeView` + "soprano
  cast" (display 11) or the toast (body 12; `danger` when an error); right the primary
  title (body 12) + "↵" keycap, a separator, "actions" + "⌘" "K" keycaps.
- **Action Panel**: a 360-wide card anchored to the bottom-right above the footer:
  heading (the item title, or "Configure Command", display 11 `textMuted`), rows 32 high
  (title body 13, keycaps right — ↵ on the primary, ⌘↵ on the secondary — destructive in
  `danger`), a filter field at the bottom ("search for actions…"), "no results" when the
  filter matches nothing.
- **Recorder**: a centered card: the item title, keycaps in display 22 ("recording…" with
  none), the conflict line in `danger`, a 2 pt `accent` countdown bar, hint "⌫ clear · ⎋
  cancel · ↵ save" (display 11).
- **Alias editor**, **confirmation**: centered cards; the alias field's placeholder
  "alias"; the confirmation shows the item title and "Are you sure?" with `RetroButton`s
  "cancel ⎋" and "<item title> ↵" (prominent, `danger`); clicking them sends ⎋ / ↵.
- **Output**: replaces the list; title row (display 11; `danger` on error), body 12 text
  view, selectable.
- **HUD**: a borderless panel 1/6 up from the display bottom, `bgRaised`, `borderStrong`,
  display 11 text, fades out after 1.5 s.
- **Empty**: display 22 `textMuted` centered in the list area.

## Tests

swift-testing, one `struct …Tests` per file, sentence-style names, `import AppKit` (never
`Foundation`) + `@testable import SopranoCastCore` / `SopranoCast`, main-actor tests
`@MainActor`. Never touch real settings, real apps, hotkeys, the keychain or the user's
defaults; system tests cover pure parts only. Test consumer-visible behavior, not wiring.

## Not copied from Raycast (phase 1)

No Raycast `.rayconfig` importer exists yet: Raycast's export never produced a file to
build against, so the user's setup was migrated into settings.json by hand (ROADMAP).
Family conventions replace: the Settings window (settings.json, live reloaded; hotkeys
and aliases also set from the Action Panel), Cloud Sync, the account, AI, the extension
Store, and themes (Soprano themes). Later phases (docs/ROADMAP.md): clipboard history,
snippets, file search, floating notes, emoji picker, window layouts and custom window
commands, move to Space, Resize/Move Window with typed values, unit/currency conversion.
