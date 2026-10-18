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
| Settings | `~/.config/soprano-cast/settings.json`; `SOPRANO_CAST_CONFIG` overrides the path |
| App state | `UserDefaults` (injectable): usage records, search history |
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
    /// backspace→delete, spacebar→space), or one non-space character → .character(lowercased).
    public init?(settingsText: String)
    public var settingsText: String { get }
    /// ⇥ ␣ ↩ ⎋ ⌫ ⌦ ← → ↑ ↓ ↖ ↘ ⇞ ⇟ F1…F20; characters uppercased ("K").
    public var symbol: String { get }
    /// Named: `keyCodes` contains `event.keyCode`. Character: `event.baseCharacters`
    /// lowercased equals the character (so ⇧⌘1 matches "1", not "!").
    public func matches(_ event: KeyEvent) -> Bool
}
```

`KeyEvent` gains `baseCharacters: String?` — the characters the key types with no
modifiers at all on the current layout (`NSEvent.characters(byApplyingModifiers: [])`).
It is added to the contract struct in `Keys.swift` with a default of nil.

### Hotkey specs (`HotkeyParsing.swift`)

```swift
extension HotkeySpec {
    /// Grammar (case-insensitive, spaces ignored):
    ///   combo:   modifiers "+" key       "cmd+shift+k", "hyper+1", "ctrl+opt+left", "fn+a"
    ///            key alone (F13–F20)     "f13"
    ///   taps:    modifiers only          "rcmd", "lopt", "cmd+opt", "fn"
    ///            (sided names lcmd rcmd lopt ropt lctrl rctrl lshift rshift; plain = any side)
    ///   double:  "double:" modifier      "double:cmd", "double:rshift"
    ///   both:    "both:" modifier        "both:cmd" (not fn)
    /// "hyper" sets `usesHyper` (combos only). nil for anything else, including a combo with
    /// no modifier whose key is not F13–F20.
    public init?(settingsText: String)
    /// Canonical spelling: "hyper" first, then ctrl, opt, shift, cmd, fn, then the key.
    public var settingsText: String { get }
    /// Keycaps: ["⌘","⇧","K"], ["✦","1"] (✦ = Hyper), ["R⌘"], ["⌘","⌘"] (double),
    /// ["L⌘","R⌘"] (both).
    public var keycaps: [String] { get }
    /// Shape names for messages: "⌘⇧K".
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
records `.combo` (named key when the key code is a `NamedKey`, else
`.character(baseCharacters)`; ⌃⌥⇧⌘ all held records `usesHyper: false` with all four —
the recorder never invents "hyper"). A keyDown without modifiers of any other key →
`.unchanged`. flagsChanged while modifiers are held → `.pending(display:)` (sided keycaps
like "R⌘" when exactly one side is down). When every modifier is up again and no
non-modifier key went down in between: one modifier tapped → `.modifierTap([its side])`;
several → `.modifierTap(set)` (sides as pressed); the same single modifier tapped again
within `doubleTapWindow` → `.doubleTap`; left and right of one modifier down at the same
time → `.bothSides`. Each `.recorded` replaces `recorded`.

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
second side goes down. Any non-modifier keyDown cancels the gesture in progress.

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
    /// keeping comments and key order.
    public static func setting(_ value: Any, at path: [String], in text: String) throws -> String
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
  "hotkeys": { "app:com.google.Chrome": "cmd+1", "window:leftHalf": "ctrl+opt+left" },
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

Rules: item ids must parse to a known `ItemKind` (unknown prefix warns, entry dropped; ids
of items that don't exist right now are kept — apps get installed later). Hotkeys parse
with `HotkeySpec(settingsText:)`; `null` removes; two entries with the same spec: the later
(by sorted id) is dropped with a warning naming both, and anything clashing with
`launcher.hotkey` is dropped. Aliases are lowercased; characters other than a–z, 0–9 and
space drop the alias with a warning; duplicate aliases warn (both kept). Quicklink ids must
match `[a-z0-9-]+` and be unique; `link` and `name` required. `hyperKey.quickPress` other
than `nothing` requires `trigger: "capsLock"` (else warns, `nothing`). Ranges clamp with a
warning. Booleans only JSON booleans; integers only whole numbers.

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
    /// existing, not disabled) then `.suggestions` (top 6 by frecency, excluding favorites,
    /// only items used at least once). Otherwise: `.calculator` (when `calculator` is non-nil,
    /// one row: `ItemID.calculatorResult`, title = formatted answer, subtitle = expression),
    /// `.results`, `.fallbacks` (settings.fallbacks that exist and aren't disabled). Empty
    /// sections are omitted.
    public static func sections(
        query: String, items: [CastItem], settings: CastSettings,
        usage: [ItemID: UsageRecord], now: Date, calculator: CalculatorResult?
    ) -> [ResultSection]
    public static let maxResults: Int   // 60
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
    /// + - * / × ÷ ^ %, parentheses, unary minus, decimals with "." or the locale's
    /// decimal separator, functions sqrt abs round floor ceil sin cos tan log (10) ln exp,
    /// constants pi π e. Division by zero, NaN and ∞ → nil.
    public static func evaluate(_ text: String, locale: Locale) -> CalculatorResult?
}
```

Ranking with a query, per non-disabled item: alias equal to the query → tier 3; alias
starting with the query → tier 2; else the best `SearchMatcher` match over title (full
weight), keywords and subtitle (half weight) → tier 1; no match → excluded. Score =
tier × 1_000_000 + match score × 1_000 + `Frecency.score` + 50 for favorites. Ties: title
`localizedStandardCompare`, then id. `matchedAlias` set for tiers 2–3; `titleRanges` from
the title match.

### Commands (`BuiltinItems.swift`, `ItemActions.swift`, `QuicklinkTemplate.swift`, `ScriptMetadataParser.swift`, `ScriptOutput.swift`, `WindowLayout.swift`)

```swift
public enum BuiltinItems {
    /// Every SystemCommand, WindowCommand and CastCommand item plus one item per quicklink,
    /// with titles, subtitles ("System", "Window Management", the quicklink's link),
    /// keywords (e.g. "fullscreen", "dark mode", "trash", "half"), icons (`.glyph`, quicklink
    /// emoji/path), `needsConfirmation`, and arguments (search commands: one "Query";
    /// quicklinks: `QuicklinkTemplate.arguments`).
    public static func items(settings: CastSettings) -> [CastItem]
}
public enum ItemActions {
    /// The Action Panel for an item, in this order (only those that apply):
    /// primary, secondary, showInFinder, copyPath/copyLink/copyResult, copyBundleID/copyName,
    /// quitApplication + hideApplication (running apps), editScript (scripts), toggleFavorite,
    /// moveFavoriteUp/Down (favorites not already first/last), setHotkey, deleteHotkey
    /// (when set), setAlias, deleteAlias (when set), disableCommand.
    public static func actions(for item: CastItem, isRunning: Bool, isFavorite: Bool,
                               canMoveFavoriteUp: Bool, canMoveFavoriteDown: Bool,
                               hasHotkey: Bool, hasAlias: Bool) -> [ItemAction]
    /// The Configure Command submenu: setHotkey, deleteHotkey (when set), setAlias, deleteAlias (when set).
    public static func configureActions(hasHotkey: Bool, hasAlias: Bool) -> [ItemAction]
    /// ↵ / ⌘↵ / ⌥↵ for an item. Primary: open ("Open Application", "Open Quicklink", "Run
    /// Script", "Run Command", calculator "Copy Answer"). Secondary: app showInFinder,
    /// quicklink copyLink, script editScript, calculator copyResult, else nil. Tertiary:
    /// app copyPath, else nil.
    public static func primary(for item: CastItem) -> ItemAction
    public static func secondary(for item: CastItem) -> ItemAction?
    public static func tertiary(for item: CastItem) -> ItemAction?
    /// In-launcher shortcuts: open ⌘O, showInFinder ⇧⌘O, copyPath/copyLink/copyResult ⇧⌘C,
    /// copyBundleID/copyName ⌥⌘C, editScript ⌘E, toggleFavorite ⌘F, moveFavoriteUp ⇧⌘↑,
    /// moveFavoriteDown ⇧⌘↓, disableCommand ⇧⌘D. Others have none.
    public static func shortcut(for action: ItemActionID) -> HotkeyCombo?
}
public struct PlaceholderContext: Sendable {
    public var clipboard: String; public var now: Date; public var uuid: String
    public init(clipboard: String, now: Date, uuid: String)
}
public enum QuicklinkTemplate {
    /// Arguments from `{argument name="x" default="y"}`, `{argument}` ("Query") and legacy
    /// `{Query}`/`{query}`, in order, deduplicated by name, at most 3; a `default` makes it optional.
    public static func arguments(in link: String) -> [ArgumentSpec]
    /// Substitutes arguments (empty → default), {clipboard}, {date} (yyyy-MM-dd), {time}
    /// (HH:mm), {uuid}. Values are percent-encoded (URL query-safe) when the link has a
    /// URL scheme, raw for file paths. A leading "~" expands to `home`.
    public static func expand(_ link: String, arguments: [String], context: PlaceholderContext, home: String) -> String
}
public enum ScriptParseError: Error, Equatable, Sendable {
    case missingRequired(String)       // "schemaVersion", "title", "mode"
    case unsupportedSchema(String)
    case badValue(key: String, value: String)
}
public enum ScriptMetadataParser {
    /// `@raycast.<key> <value>` lines in `#` or `//` comments: schemaVersion (1), title, mode,
    /// packageName (default: `directoryName`), icon (emoji → .emoji; https URL → .url; else a
    /// path relative to the script's folder → .file), iconDark (ignored), currentDirectoryPath,
    /// needsConfirmation, refreshTime ("10s" "1m" "12h" "1d", minimum 10 s), argument1…3
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
    /// and size (scaled when the target is smaller), clamped inside `target`.
    public static func moved(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect
    /// Whether `frame` equals `expected` within `tolerance`.
    public static func matches(_ frame: CGRect, _ expected: CGRect, tolerance: CGFloat) -> Bool
}
```

Window rules: halves/thirds/fourths/quarters/sixths split the visible frame into equal
regions; maximize fills it (minus gaps); almostMaximize = 90 % centered; maximizeHeight /
maximizeWidth keep the other axis; reasonableSize = 60 % of each side capped at 1025 × 900,
centered; center keeps the size (clamped), centered; centerHalf = half width, full height,
centered; moveUp/Down/Left/Right keep the size and touch that edge (with gap), the other
coordinate unchanged; makeLarger/makeSmaller grow/shrink by 10 % of the visible size around
the window center, clamped to the visible frame, at least 200 × 150.

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

Key map (Raycast's). Every context: ⌘W closeWindow, ⌘Esc popToRoot.
- **root**: ↑ moveUp (historyPrevious when `selectionAtTop`), ↓ moveDown (historyNext when
  `selectionAtBottom`), ⌃P/⌃N (emacs, both), ⌃K/⌃J (vim, both); ⌥↑/⌥↓ pageUp/pageDown;
  ⌘↑/⌘↓ sectionUp/sectionDown; ⇧⌘↑/⇧⌘↓ moveFavoriteUp/Down; ↵ runPrimary; ⌘↵ runSecondary;
  ⌥↵ runTertiary; ⌘K toggleActionPanel; ⇧⌘, configureCommand; ⌘, openSettings; ⌘F
  toggleFavorite; ⇧⌘D disableCommand; the other `ItemActions.shortcut` combos →
  `runAction`; Tab nextArgument and ⇧Tab previousArgument when `selectionHasArguments` or an
  argument is focused; Esc back. Everything else (typing, ⌃F/⌃B, ⌘A/⌘C/⌘V, ←/→) → nil.
- **actionPanel**: ↑/↓ and the navigation bindings move; ↵ runPrimary (the selected
  action); ⌘↵ runSecondary; ⌘K toggleActionPanel; Esc back; action shortcuts → `runAction`;
  typing → nil (filter field).
- **hotkeyRecorder**: always nil.
- **aliasEditor**: ↵ runPrimary (save), Esc back, else nil.
- **output**: ↵ and Esc back, else nil (the text view handles ⌘C/⌘A).
- **confirmation**: ↵ runPrimary (confirm), Esc back, else nil.

## System APIs

```swift
@MainActor final class LiveAppCatalog: ItemSource { init(extraDirectories: [String]) ; func setExtraDirectories(_: [String]) }
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
@MainActor final class ScriptCatalog: ItemSource { init(directories: [String]); func setDirectories(_: [String]); func reload(); func script(for id: ItemID) -> ScriptCommand? }
@MainActor final class ScriptRunner { init(); func run(_ script: ScriptCommand, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void) }
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
}
enum KeyboardLayout {      // main thread only
    /// The key code that types `character` (lowercased) with no modifiers on the current
    /// layout (UCKeyTranslate over codes 0…127), nil when none does.
    static func keyCode(for character: Character) -> UInt16?
    /// The character key code `keyCode` types with no modifiers on the current layout.
    static func character(for keyCode: UInt16) -> Character?
}
```

- **Apps**: `NSMetadataQuery` for `kMDItemContentTypeTree == "com.apple.application-bundle"`
  scoped to /Applications, /System/Applications (both with Utilities), ~/Applications,
  /System/Library/CoreServices/Applications, /System/Library/CoreServices/Finder.app's
  folder and `extraDirectories`, plus a direct scan of those folders at start (Spotlight can
  be off). Skips apps nested inside other bundles and `LSBackgroundOnly` apps. One item per
  bundle id (prefer /Applications, then /System/Applications, then the shortest path); id
  `app:<bundle id>` (`app:<path>` without one); title = display name without ".app";
  subtitle = folder, ~-abbreviated; keywords = bundle name, executable name; icon `.file(path)`.
- **Open app** (`AppActions.open`): running → unhide and activate; if it then has no
  windows, `NSWorkspace.openApplication(at:configuration:)` so it reopens a window (a Dock
  click). Not running → launch. (Your ⌘1 → Chrome hotkey runs exactly this.)
- **Icons**: file icons from `NSWorkspace.icon(forFile:)`, emoji drawn into an image,
  glyphs from SF Symbols tinted with the theme accent, remote icons fetched once into the
  Caches folder; all cached per (icon, size).
- **System commands**: lockScreen = `SACLockScreenImmediate` (login.framework via dlsym),
  falling back to posting ⌃⌘Q; sleep = `pmset sleepnow`; sleepDisplays = `pmset
  displaysleepnow`; restart/shutDown/logOut = Apple events `aevt/rrst`, `aevt/shut`,
  `aevt/rlgo` to loginwindow; emptyTrash = Finder `empty trash` Apple event; ejectAllDisks =
  `NSWorkspace.unmountAndEjectDevice` for every ejectable volume; toggleSystemAppearance =
  System Events `appearance preferences` Apple event; quitAllApplications = terminate every
  regular app except Finder and Soprano Cast; hideOtherApplications = hide every regular app
  except the frontmost; toggleHiddenFiles = flip `com.apple.finder AppleShowAllFiles` and
  relaunch Finder. Each returns `.hud("<title>")` or `.toast(error, isError: true)`.
  `Info.plist` carries `NSAppleEventsUsageDescription` for the Automation prompts.
- **Scripts**: `ScriptCatalog` scans each directory (and one level of subfolders) for
  regular files without ".template." whose metadata parses; watches the folders with the
  vendored `FileSystemWatcher`; item id `script:<path>`, subtitle = package name, icon from
  metadata or `.glyph(.script)`. Inline-mode scripts run on load and every `refreshSeconds`
  (first 10 only) and show their last output line as the subtitle. `ScriptRunner` runs the
  file directly when executable, else via its shebang interpreter; arguments are positional;
  cwd = `currentDirectoryPath` or the script's folder; PATH = /opt/homebrew/bin:/usr/local/bin:
  + inherited. Outcome by mode: silent → `.hud(lastLine ?? title)`, compact →
  `.toast(lastLine ?? title)`, fullOutput → `.output(title, stdout+stderr ANSI-stripped)`,
  inline → `.toast(lastLine)` and the subtitle refreshes; non-zero exit →
  `.toast(lastLine ?? "Script failed", isError: true)` (fullOutput: `.output(…, isError: true)`).
- **LiveItemRunner**: application → `AppActions.open`; systemCommand →
  `SystemCommandRunner`; windowCommand → `WindowManaging.perform` (`.hud(message)` when it
  returns one, else `.done(closeLauncher: true)`); quicklink → `QuicklinkOpener`; script →
  `ScriptRunner`; castCommand searchGoogle/searchDuckDuckGo → open the engine URL with the
  query, the rest → `castCommand` closure; calculator → copy the answer, `.hud("Copied")`.
  Copy actions write the pasteboard and return `.hud("Copied")`.
- **Window manager**: AX focused window of the frontmost app (position/size are Quartz);
  the display holding most of the window (NSScreen frames converted with `Geometry`);
  `WindowLayout.frame`; set position, size, then position again (AX applies size within the
  current display bounds); remembers the frame before each command per CGWindowID
  (`_AXUIElementGetWindow` via dlsym) for `restore`; toggleFullscreen flips `AXFullScreen`;
  previous/nextDisplay move with `WindowLayout.moved` over displays sorted by x; halves
  `.moveToDisplay`: Left Half on a window already the left half moves it to the right half of
  the display to the left (and mirrored). Without Accessibility: returns
  "Window Management needs Accessibility".
- **Hotkey center**: combos without fn → Carbon `RegisterEventHotKey` (works without
  Accessibility; fires even while the launcher is key); character keys resolve through
  `KeyboardLayout.keyCode(for:)` and every registration is redone when the input source
  changes (`com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged`). Modifier-only
  specs (taps, double taps, both sides) and fn combos → a CGEventTap on the main run loop
  (listen-only for flagsChanged; fn combos need the active tap to swallow their keyDown)
  feeding `ModifierGestureDetector`; needs Accessibility, reported as a `HotkeyFailure` when
  missing. `suspend()` unregisters every Carbon hotkey and mutes the tap (the recorder must
  receive ⌘1 itself); `resume()` re-registers.
- **Hyper key**: `hidutil property --set` maps the trigger (Caps Lock 0x700000039, right ⌘
  0x7000000E7, right ⌥ 0x7000000E6, right ⌃ 0x7000000E4, right ⇧ 0x7000000E5) to F18
  (0x70000006D); an active event tap holds a "hyper down" flag while F18 is down and adds
  ⌃⌥⇧⌘ (⌃⌥⌘ without Shift) to every key event meanwhile, so Carbon hotkeys registered
  with those modifiers fire; F18 released with no key in between → `quickPress` (toggle Caps
  Lock via `IOHIDSetModifierLockState`, or post Escape). `remove()` clears the mapping (also
  on quit). Returns an error message when the mapping fails or Accessibility is missing.

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
    /// A hotkey or the CLI: runs the item without showing the launcher. An item with required
    /// arguments and none given opens the launcher on it with its first argument focused.
    func run(itemID: ItemID, arguments: [String])
    func settingsDidChange()
    /// For the harness and tests: the current state.
    var state: LauncherStateSnapshot { get }
}
struct LauncherStateSnapshot: Equatable {   // defined by the controller
    var query: String; var selectedID: ItemID?; var rowIDs: [ItemID]; var overlay: String  // "none", "actionPanel", …
    var argumentValues: [String]; var footerToast: String?
}
enum LauncherModelBuilder {
    static func model(...) -> LauncherViewModel    // controller → view model; signature the controller's choice
}
```

Controller behavior:
- Builds `allItems` from its sources plus `BuiltinItems.items(settings:)`, refreshed on
  `onChange` and `settingsDidChange`. Ranks with `Ranker.sections` on every query change
  (calculator from `Calculator.evaluate(query, locale: .current)`); selection resets to the
  first row on a query change.
- Keys: `presenter.onKeyEvent` → in `.hotkeyRecorder` every event goes to `HotkeyRecorder`;
  else `LauncherKeyRouter.command(for:input:)` → execute → true; nil → false.
- **runPrimary**: the selected row's primary action. An item with required arguments whose
  fields are empty focuses the first empty field instead (a toast "Fill in <name>" when
  already focused). `needsConfirmation` → the confirmation overlay first. Running records
  usage (`Frecency.recording`) and the query in `SearchHistory`, then presents the
  `RunOutcome`: `.done(close)` closes when asked; `.hud` closes and shows the HUD; `.toast`
  shows it in the footer for 3 s; `.output` opens the output overlay. Fallback rows run their
  item with the query as the first argument.
- **runSecondary/runTertiary/runAction** → `ItemActions` lookups → `runner.perform` or the
  settings actions below. Action Panel: lists `ItemActions.actions` for the selection,
  filtered by its text (`SearchMatcher`), ↵ runs the selected one; Configure Command opens
  `configureActions` in the same panel.
- **Settings actions** (all through `environment.editSettings`; the settings center reloads
  and calls `settingsDidChange`): toggleFavorite appends/removes in `favorites`;
  moveFavoriteUp/Down swaps; disableCommand adds to `disabled` (toast "Disabled <title>");
  setHotkey opens the recorder overlay (calls `hotkeys.suspend()`; every `.recorded` shows
  keycaps and the owner from `HotkeyConflicts.owner` in red ("Used by <title>"); the
  launcher's own hotkey shows "Used by Soprano Cast" and can't be saved; a recorded spec
  starts a 1.5 s countdown that saves `hotkeys.<id>`, overwriting a conflicting owner by
  removing its entry; `.commit` saves now; `.cleared` removes; `.cancelled` closes;
  `hotkeys.resume()` on leaving); deleteHotkey removes; setAlias opens the alias editor
  (lowercase a–z, 0–9, space; invalid characters show an error), ↵ saves `aliases.<id>`;
  deleteAlias removes.
- **back** (Esc): closes the topmost overlay; with none, closes the window. **popToRoot**:
  clears query, arguments, overlays, selection. **closeWindow** hides. Reopening after more
  than `popToRootSeconds` since hiding pops to root first; within it, everything is as left.
- **History**: ↑ on the first row (or empty list) puts the previous history query into the
  field; ↓ on the last row the next; typing resets the cursor.
- Arguments: the selected item's `arguments` become argument fields in the search bar
  (values kept per item while the selection doesn't change); Tab/⇧Tab cycle focus query →
  args; typing an alias + space focuses the first argument (Raycast).
- `run(itemID:)` (hotkeys): runs without showing; HUDs show on `environment.screenFrame`.
  `.launcher` target → `toggle()`.
- Shows on `environment.screenFrame(settings.launcher.screen)`; `onResignKey` hides when
  `closeOnFocusLoss`.
- Model: placeholder "Search for apps and commands…"; row accessory = `ItemKind.label`
  (calculator: the expression; scripts: their package name); alias badge; hotkey keycaps
  (`HotkeySpec.keycaps`); footer primary title from `ItemActions.primary`; empty text
  "No results" with a query, "Type to search apps and commands" without.

## Shell

- `main.swift`: before `NSApplication`, `snapshot` → `SnapshotCommand.run(arguments:)`;
  `toggle`, `open`, `list`, `help`, `--help` → `CLIClient.run(arguments:)`; both exit.
  Otherwise the GUI with `.accessory` policy and `AppDelegate`.
- `AppDelegate` (composition root): single-instance guard; `SettingsCenter.shared.start()`;
  `ThemeCenter.shared.start()`; `LiveAppCatalog`, `ScriptCatalog`, `LiveIconProvider`,
  `LiveWindowManager`, `ScriptRunner`, `SystemCommandRunner`, `LiveItemRunner` (cast
  commands: openSettings opens settings.json, reloadScripts, quit), `HotkeyCenter`,
  `HyperKeyController`, `LauncherWindow`, `LauncherController` with an environment over
  `SettingsCenter`, `ThemeCenter`, `AppStateStore` (UserDefaults) and
  `DispatchQueue.main.asyncAfter`; `hotkeys.onTrigger` → `.launcher` → `toggle()`,
  `.item(id)` → `run(itemID:arguments: [])`; `hotkeys.setBindings(settings.hotkeyBindings,
  hyperKey:)` at start and on every settings change (failures shown in the menu); Hyper key
  applied and removed on quit; `MenuBarController`; `LoginItem.sync`; `CLIServer`. First
  launch: permissions window when Accessibility is missing (needed for window management,
  modifier-only hotkeys and the Hyper key; app/quicklink/script hotkeys work without it).
  Reopen (Spotlight/Finder) → `toggle()`.
- `SettingsFile` / `SettingsCenter` / `ThemeCenter`: Soprano Tab's
  (`~/git/private/soprano-tab/Sources/SopranoTab/Shell/`) with Cast names; `SettingsCenter`
  gains `edit(_ edit: SettingsEdit) throws` (via `SettingsEditor`).
- `AppStateStore(defaults: UserDefaults = .standard)`: usage records and search history as
  JSON data under `castUsage` / `castHistory`.
- `MenuBarController`: status item (programmatic template icon: a square with a slanted
  beam), menu: "Open Soprano Cast" (launcher hotkey as key equivalent text), "Settings…"
  (⌘,), a disabled "settings.json: N warnings" line, a disabled "N hotkeys need attention"
  line (tooltip: the failures), "Permissions…", "Launch at Login" (writes
  `app.startAtLogin`), "About Soprano Cast", "Quit Soprano Cast" (⌘Q). Hidden while
  `showMenuBarIcon` is false.
- `Permissions` + `PermissionsWindowController(status:)`: Soprano Tab's, with one row:
  Accessibility — "window management, modifier-only hotkeys and the Hyper key".
- `CLIServer(controller:)` / `CLIClient`: Soprano Tab's mechanics. `SopranoCast toggle`,
  `SopranoCast open <item id> [argument…]`, `SopranoCast list` (JSON `CLIItem`s sorted by
  title), `help`.

## Fixtures and the snapshot harness

`FixtureCatalog` (an `ItemSource` with ~14 apps — Google Chrome, Safari, Soprano, Soprano
Git, Soprano Tab, Slack, Mail, Notes, Music, Finder, System Settings, Xcode, Aside,
WhatsApp — plus 3 script commands), `FixtureIcons` (square letter tiles, glyph drawings),
`FixtureRunner` (records runs/actions, returns scripted outcomes), `FixtureHotkeys`
(records bindings, suspend/resume). Fixed `now`, usage (Chrome, Soprano, Slack used) and
history.

`SopranoCast snapshot --out <png> [--query "<text>"] [--keys "<token> …"]
[--settings <jsonc>] [--screen 1512x982] [--theme <id>] [--report <json>]` builds the real
`LauncherController` + `LauncherWindow` on fixtures offscreen (no Dock icon, no state),
shows the launcher, types `--query` through `onQueryChange`, replays `--keys` through
`onKeyEvent` (tokens: `down up return esc tab shift+tab cmd+k cmd+return opt+return
shift+cmd+, cmd+f cmd+esc ctrl+n …`, a single character types it; `rec:<hotkey>` replays the
key events of a hotkey into the recorder), and writes `renderSnapshot`. `--report` writes
JSON: query, rows (ids), selected id, overlay, runs (`FixtureRunner` log), settings edits.

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
  heading (the item title, display 11), rows 32 high (title body 13, keycaps right,
  destructive in `danger`), a filter field at the bottom ("search for actions…").
- **Recorder**: a centered card: the item title, keycaps in display 22, the conflict line in
  `danger`, a 2 pt `accent` countdown bar, hint "⌫ clear · ⎋ cancel · ↵ save" (display 11).
- **Alias editor**, **confirmation**: centered cards; confirmation buttons `RetroButton`
  ("cancel ⎋", "confirm ↵" prominent, `danger` for destructive).
- **Output**: replaces the list; title row, monospace body 12 text view, selectable.
- **HUD**: a borderless panel 1/6 up from the display bottom, `bgRaised`, `borderStrong`,
  display 11 text, fades out after 1.5 s.
- **Empty**: display 22 `textMuted` centered in the list area.

## Tests

swift-testing, one `struct …Tests` per file, sentence-style names, `import AppKit` (never
`Foundation`) + `@testable import SopranoCastCore` / `SopranoCast`, main-actor tests
`@MainActor`. Never touch real settings, real apps, hotkeys, the keychain or the user's
defaults; system tests cover pure parts only. Test consumer-visible behavior, not wiring.

## Not copied from Raycast (phase 1)

Family conventions replace: the Settings window (settings.json, live reloaded; hotkeys
and aliases also set from the Action Panel), Cloud Sync, the account, AI, the extension
Store, and themes (Soprano themes). Later phases (docs/ROADMAP.md): clipboard history,
snippets, file search, floating notes, emoji picker, window layouts and custom window
commands, move to Space, Resize/Move Window with typed values, unit/currency conversion.
