import AppKit
import SopranoCastCore

/// What a snapshot run ended with, written by `--report` for agents to check behavior
/// without reading pixels.
struct SnapshotReport: Equatable, Encodable {
    var query: String
    /// Every listed row's item id, in order.
    var rows: [String]
    /// The selected row's item id.
    var selected: String?
    /// `LauncherStateSnapshot.overlay`: "none", "actionPanel", "recorder", …
    var overlay: String
    /// `FixtureRunner.log`.
    var runs: [String]
    /// `FixtureSettingsStore.edits`.
    var edits: [String]
    var footerToast: String?

    private enum CodingKeys: String, CodingKey {
        case query, rows, selected, overlay, runs, edits, footerToast
    }

    /// Writes missing values as `null` instead of omitting them.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(rows, forKey: .rows)
        try container.encode(selected, forKey: .selected)
        try container.encode(overlay, forKey: .overlay)
        try container.encode(runs, forKey: .runs)
        try container.encode(edits, forKey: .edits)
        try container.encode(footerToast, forKey: .footerToast)
    }

    /// Pretty-printed JSON with sorted keys.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// `SopranoCast snapshot --out <png> …` (see `usage`).
///
/// Runs the real `LauncherController` and `LauncherWindow` on fixtures offscreen: no Dock
/// icon, no activation, no persisted state, no hotkeys, no permission. Shows the launcher,
/// types `--query`, replays `--keys`, then writes the panel over a drawn desktop as a PNG
/// (and the report as JSON). Time stands still unless a `wait` token lets it pass.
@MainActor
enum SnapshotCommand {
    /// One `--keys` token.
    enum KeyToken: Equatable {
        /// A key pressed with modifiers: the modifiers go down (flagsChanged), the key goes
        /// down, the modifiers come up. Unconsumed character keys type into the focused field.
        case press(KeySpec, ModifierSet)
        /// `rec:<hotkey>`: the key events that record the hotkey in the recorder.
        case record(HotkeySpec)
        /// `wait`, `wait:<ms>`: lets virtual time pass, running scheduled work that falls due.
        case wait(milliseconds: Int)
    }

    struct Options: Equatable {
        var out: URL
        var query: String?
        var keys: [KeyToken] = []
        var settings: URL?
        var screenSize = SnapshotCommand.defaultScreenSize
        var theme: String?
        var report: URL?
        /// Renders the settings window on this tab instead of the launcher.
        var settingsWindow: SettingsTab?
        /// Extensions: "group:<group>" or an item id to select.
        var select: String?
        /// Extensions: the table's search text.
        var filter: String?
        /// "launcher" or an item id whose hotkey the recorder card records (`--keys` go to it).
        var record: String?
    }

    enum OptionError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case unknownOption(String)
        case missingOut
        case badScreen(String)
        case unknownKeyToken(String)
        case badRecording(String)
        case badWait(String)
        case badSettingsTab(String)
        /// A settings-window option without `--settings-window`.
        case needsSettingsWindow(String)
        /// A launcher option with `--settings-window`.
        case launcherOnly(String)

        var description: String {
            switch self {
            case let .missingValue(option): "\(option) needs a value"
            case let .unknownOption(option): "unknown option \(option)"
            case .missingOut: "--out <png> is required"
            case let .badScreen(value): "--screen must be WIDTHxHEIGHT, at least 800x600, got \(value)"
            case let .unknownKeyToken(token):
                "unknown key \"\(token)\" (a named key, a character, modifiers+key like cmd+k, rec:<hotkey> or wait)"
            case let .badRecording(token):
                "\"\(token)\": rec: needs a settings.json hotkey typed on a US keyboard (rec:cmd+1, rec:rcmd, rec:double:cmd)"
            case let .badWait(token): "\"\(token)\": wait takes 0…600000 milliseconds (wait:1500)"
            case let .badSettingsTab(value):
                "--settings-window takes \(SettingsTab.allCases.map(\.rawValue).joined(separator: ", ")), got \(value)"
            case let .needsSettingsWindow(option): "\(option) needs --settings-window"
            case let .launcherOnly(option): "\(option) is for the launcher, not --settings-window"
            }
        }
    }

    nonisolated static let defaultScreenSize = CGSize(width: 1512, height: 982)
    /// The fixture display's menu bar; the launcher's visible frame is the screen below it.
    nonisolated static let menuBarHeight: CGFloat = 33
    /// What a bare `wait` lets pass: longer than the recorder's 1.5 s auto-save countdown,
    /// shorter than a footer toast's 3 s.
    nonisolated static let defaultWaitMilliseconds = 2000
    nonisolated static let maxWaitMilliseconds = 600_000

    nonisolated static let usage = """
    usage: SopranoCast snapshot --out <png> [--query "<text>"] [--keys "<token> …"]
                                [--settings <jsonc>] [--screen 1512x982] [--theme <id>]
                                [--report <json>]
           SopranoCast snapshot --out <png> --settings-window <general|extensions|advanced>
                                [--select <item-id|group:<group>>] [--filter "<text>"]
                                [--record <item-id|launcher>] [--keys "<token> …"]
                                [--settings <jsonc>] [--theme <id>] [--report <json>]
      --settings-window renders the settings window (1120x700) instead of the launcher;
        --select picks a row of Extensions (group:applications, group:quicklinks,
        group:scriptCommands, group:sopranoCast, group:system, group:systemSettings,
        group:windowManagement or an item id), --filter searches its table, --record
        opens the recorder card and --keys replay into it.
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
    """

    // MARK: - Options

    nonisolated static func parse(_ arguments: [String]) throws -> Options {
        var out: URL?
        var options = Options(out: URL(fileURLWithPath: "/dev/null"))
        var index = 0
        func value(_ option: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw OptionError.missingValue(option) }
            return arguments[index]
        }
        func fileURL(_ path: String) -> URL {
            URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        }
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--out": out = fileURL(try value(option))
            case "--report": options.report = fileURL(try value(option))
            case "--settings": options.settings = fileURL(try value(option))
            case "--theme": options.theme = try value(option)
            case "--query": options.query = try value(option)
            case "--keys":
                options.keys = try value(option).split(whereSeparator: \.isWhitespace).map { try keyToken(String($0)) }
            case "--screen":
                let text = try value(option)
                let parts = text.lowercased().split(separator: "x", omittingEmptySubsequences: false).map { Int($0) }
                guard parts.count == 2, let width = parts[0], let height = parts[1], width >= 800, height >= 600 else {
                    throw OptionError.badScreen(text)
                }
                options.screenSize = CGSize(width: width, height: height)
            case "--settings-window":
                let text = try value(option)
                guard let tab = SettingsTab(rawValue: text) else { throw OptionError.badSettingsTab(text) }
                options.settingsWindow = tab
            case "--select": options.select = try value(option)
            case "--filter": options.filter = try value(option)
            case "--record": options.record = try value(option)
            default:
                throw OptionError.unknownOption(option)
            }
            index += 1
        }
        guard let out else { throw OptionError.missingOut }
        options.out = out
        if options.settingsWindow == nil {
            for (option, value) in [("--select", options.select), ("--filter", options.filter), ("--record", options.record)] where value != nil {
                throw OptionError.needsSettingsWindow(option)
            }
        } else {
            if options.query != nil { throw OptionError.launcherOnly("--query") }
            if arguments.contains("--screen") { throw OptionError.launcherOnly("--screen") }
        }
        return options
    }

    /// One `--keys` token (grammar in `usage`).
    nonisolated static func keyToken(_ text: String) throws -> KeyToken {
        let lowered = text.lowercased()
        if lowered == "wait" { return .wait(milliseconds: defaultWaitMilliseconds) }
        if lowered.hasPrefix("wait:") {
            guard let milliseconds = Int(lowered.dropFirst(5)), (0...maxWaitMilliseconds).contains(milliseconds) else {
                throw OptionError.badWait(text)
            }
            return .wait(milliseconds: milliseconds)
        }
        if lowered.hasPrefix("rec:") {
            guard let spec = HotkeySpec(settingsText: String(text.dropFirst(4))), isReplayable(spec) else {
                throw OptionError.badRecording(text)
            }
            return .record(spec)
        }
        if text.count == 1, let character = text.first {
            guard let press = characterPress(character) else { throw OptionError.unknownKeyToken(text) }
            return .press(press.key, press.modifiers)
        }
        // "modifiers+key"; the key itself may be "+" ("cmd++").
        var modifiers: ModifierSet = []
        var keyText = text
        if let plus = text.dropLast().lastIndex(of: "+") {
            guard let parsed = ModifierSet(settingsText: String(text[..<plus])) else {
                throw OptionError.unknownKeyToken(text)
            }
            modifiers = parsed
            keyText = String(text[text.index(after: plus)...])
        }
        // Case-insensitive like settings.json: "cmd+K" is ⌘K; "cmd+!" is still ⇧⌘1.
        if keyText.count == 1, let character = keyText.lowercased().first {
            guard let press = characterPress(character) else { throw OptionError.unknownKeyToken(text) }
            return .press(press.key, modifiers.union(press.modifiers))
        }
        // A named key, or a physical key by position ("cmd+key:'", "key:0x27").
        switch KeySpec(settingsText: keyText) {
        case .named(let named)?: return .press(.named(named), modifiers)
        case .physical(let code)?: return .press(.physical(code), modifiers)
        case .character?, nil: throw OptionError.unknownKeyToken(text)
        }
    }

    /// The unshifted key and the Shift a typed character needs on a US keyboard.
    private nonisolated static func characterPress(_ character: Character) -> (key: KeySpec, modifiers: ModifierSet)? {
        if character == " " { return (.named(.space), []) }
        if characterKeyCodes[character] != nil { return (.character(character), []) }
        let lowered = Character(character.lowercased())
        if lowered != character, characterKeyCodes[lowered] != nil { return (.character(lowered), .shift) }
        if let base = shiftedToBase[character] { return (.character(base), .shift) }
        return nil
    }

    /// Whether `spec`'s keys exist on the US keyboard the replay types on. Named and
    /// physical keys are key codes already; only a character needs a US key that types it.
    private nonisolated static func isReplayable(_ spec: HotkeySpec) -> Bool {
        guard case .combo(let combo) = spec, case .character(let character) = combo.key else { return true }
        return characterKeyCodes[character] != nil
    }

    // MARK: - Running

    static func run(arguments: [String]) -> Never {
        let options: Options
        do {
            options = try parse(arguments)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n\(usage)\n".utf8))
            exit(2)
        }
        // In-memory registration domain only: nothing is written to the user's defaults.
        UserDefaults.standard.register(defaults: [
            "ApplePersistenceIgnoreState": true,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        let app = NSApplication.shared
        // No Dock icon, no menu bar, never activated: nothing appears on the user's screen.
        app.setActivationPolicy(.prohibited)
        do {
            let result = try render(options)
            try writePNG(result.image, to: options.out)
            if let reportURL = options.report {
                try createParentDirectory(of: reportURL)
                try result.report.jsonData().write(to: reportURL)
            }
            print(options.out.path)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }

    /// The testable core: the rendered image (screen size × 2, or the settings window × 2)
    /// and the report.
    static func render(_ options: Options) throws -> (image: CGImage, report: SnapshotReport) {
        let store = try settingsStore(options)
        // Menus, pop-ups and scrollers draw in the fixture theme's appearance.
        NSApplication.shared.appearance = FixtureTheme.resolve(store.settings.theme).appearance.nsAppearance
        if let tab = options.settingsWindow {
            return try renderSettingsWindow(options, tab: tab, store: store)
        }
        let screen = CGRect(origin: .zero, size: options.screenSize)
        let visible = CGRect(x: 0, y: 0, width: screen.width, height: screen.height - menuBarHeight)
        let support = FixturePresenterSupport(settingsStore: store, visibleFrame: visible)
        let runner = FixtureRunner()

        LauncherWindow.offscreen = true
        let presenter = ModelRecordingPresenter(LauncherWindow())
        let controller = LauncherController(
            sources: [FixtureCatalog()],
            icons: FixtureIcons(theme: support.environment.theme),
            runner: runner,
            presenter: presenter,
            hotkeys: FixtureHotkeys(),
            environment: support.environment
        )
        // The settings center notifies the app after every write; the controller reloads.
        store.onChange = { [weak controller] in controller?.settingsDidChange() }

        controller.show()
        if let query = options.query {
            presenter.onQueryChange?(query)
        }
        var replay = KeyReplay(hyperIncludesShift: store.settings.hyperKey.includeShift)
        for token in options.keys {
            if case .wait(let milliseconds) = token {
                try support.advance(milliseconds: milliseconds)
                replay.pass(milliseconds: milliseconds)
                continue
            }
            for event in replay.events(for: token) {
                // A closed launcher has no key window: the rest of the token goes nowhere.
                guard controller.isVisible else { break }
                if presenter.onKeyEvent?(event) != true, event.kind == .keyDown {
                    typeUnhandled(event, into: presenter)
                }
            }
        }

        let appearance = FixtureTheme.resolve(store.settings.theme).appearance
        guard let backdrop = backdrop(size: options.screenSize, scale: 2, appearance: appearance) else {
            throw FixtureError(description: "the backdrop did not render")
        }
        let image = presenter.renderSnapshot(screenFrame: screen, scale: 2, backdrop: backdrop) ?? backdrop
        let state = controller.state
        let report = SnapshotReport(
            query: state.query,
            rows: state.rowIDs.map(\.rawValue),
            selected: state.selectedID?.rawValue,
            overlay: state.overlay,
            runs: runner.log,
            edits: store.edits,
            footerToast: state.footerToast
        )
        return (image, report)
    }

    /// The settings window on fixtures: the launcher (offscreen, never shown) supplies the
    /// items as in the app; `--select`, `--filter`, `--record` and `--keys` drive it. The
    /// report's `query` is the filter, `rows` the Extensions rows, `selected` the selected row,
    /// `overlay` "recorder" or "none", `runs` what the window asked the app to do, and
    /// `footerToast` the status line.
    private static func renderSettingsWindow(_ options: Options, tab: SettingsTab, store: FixtureSettingsStore) throws -> (image: CGImage, report: SnapshotReport) {
        let support = FixturePresenterSupport(
            settingsStore: store,
            visibleFrame: CGRect(origin: .zero, size: defaultScreenSize)
        )
        LauncherWindow.offscreen = true
        let controller = LauncherController(
            sources: [FixtureCatalog()],
            icons: FixtureIcons(theme: support.environment.theme),
            runner: FixtureRunner(),
            presenter: LauncherWindow(),
            hotkeys: FixtureHotkeys(),
            environment: support.environment
        )
        let window = SettingsWindowController(
            environment: support.settingsWindowEnvironment(items: { controller.allItems }),
            icons: FixtureIcons(theme: support.environment.theme),
            hotkeys: FixtureHotkeys(),
            keyCode: LauncherController.layoutKeyCode
        )
        store.onChange = { [weak controller, weak window] in
            controller?.settingsDidChange()
            window?.settingsDidChange()
        }
        window.show(tab: tab)
        if let filter = options.filter {
            window.extensions.setFilter(filter)
        }
        if let select = options.select {
            window.extensions.select(try selection(select, items: controller.allItems))
            // Like a click on the row: the table takes the keyboard (pill with the tick).
            window.window?.makeFirstResponder(window.extensions.tableView)
        }
        if let record = options.record {
            let target: HotkeyTarget = record == "launcher" ? .launcher : .item(ItemID(rawValue: record))
            let title = record == "launcher" ? "Soprano Cast" : controller.allItems.first { $0.id.rawValue == record }?.title
            guard let title else { throw FixtureError(description: "--record: no item \(record)") }
            window.recordHotkey(for: target, title: title)
        }
        var replay = KeyReplay(hyperIncludesShift: store.settings.hyperKey.includeShift)
        for token in options.keys {
            if case .wait(let milliseconds) = token {
                try support.advance(milliseconds: milliseconds)
                replay.pass(milliseconds: milliseconds)
                continue
            }
            for event in replay.events(for: token) where window.isRecording {
                window.receive(event)
            }
        }

        guard let image = window.renderImage(scale: 2) else {
            throw FixtureError(description: "the settings window did not render")
        }
        let selected: String? = switch window.extensions.selection {
        case .group(let group)?: "group:\(group.rawValue)"
        case .item(let id)?: id.rawValue
        case nil: nil
        }
        let report = SnapshotReport(
            query: window.extensions.filter,
            rows: tab == .extensions ? window.extensions.listedIDs : [],
            selected: tab == .extensions ? selected : nil,
            overlay: window.isRecording ? "recorder" : "none",
            runs: support.windowLog,
            edits: store.edits,
            footerToast: window.statusText
        )
        return (image, report)
    }

    /// `group:<group>` or an item id that exists among `items`.
    private static func selection(_ text: String, items: [CastItem]) throws -> ExtensionsSettingsPane.Selection {
        if text.hasPrefix("group:") {
            let name = String(text.dropFirst("group:".count))
            guard let group = ExtensionGroup(rawValue: name) else {
                let known = ExtensionGroup.allCases.map { "group:\($0.rawValue)" }.joined(separator: ", ")
                throw FixtureError(description: "--select: unknown group \(name) (\(known))")
            }
            return .group(group)
        }
        guard items.contains(where: { $0.id.rawValue == text }) else {
            throw FixtureError(description: "--select: no item \(text)")
        }
        return .item(ItemID(rawValue: text))
    }

    /// `SettingsTemplate.text` or `--settings`, with `--theme` over it.
    private static func settingsStore(_ options: Options) throws -> FixtureSettingsStore {
        if let theme = options.theme, theme != ThemeCenter.followSopranoID, !FixtureSettingsStore.knownThemeIDs.contains(theme) {
            let known = ([ThemeCenter.followSopranoID] + AppTheme.options.map(\.id)).joined(separator: ", ")
            throw FixtureError(description: "unknown theme \(theme) (\(known))")
        }
        guard let url = options.settings else {
            return try FixtureSettingsStore(themeOverride: options.theme)
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FixtureError(description: "cannot read \(url.path): \(error.localizedDescription)")
        }
        let store: FixtureSettingsStore
        do {
            store = try FixtureSettingsStore(text: text, themeOverride: options.theme)
        } catch {
            throw FixtureError(description: "\(url.path): \(error)")
        }
        for issue in store.issues {
            FileHandle.standardError.write(Data("snapshot: \(url.lastPathComponent): \(FixtureSettingsStore.describe(issue))\n".utf8))
        }
        return store
    }

    /// What the focused text field does with a key the launcher didn't consume: a character
    /// key or Space (alone or with Shift) appends its characters, Delete removes the last
    /// character; anything else does nothing.
    private static func typeUnhandled(_ event: KeyEvent, into presenter: ModelRecordingPresenter) {
        guard event.modifiers.subtracting([.shift, .function]).isEmpty,
              let field = presenter.focusedField()
        else { return }
        if event.keyCode == NamedKey.delete.keyCodes[0] {
            if !field.text.isEmpty { field.change(String(field.text.dropLast())) }
            return
        }
        let types = event.keyCode == NamedKey.space.keyCodes[0] || characterKeyCodes.values.contains(event.keyCode)
        guard types, let characters = event.characters else { return }
        field.change(field.text + characters)
    }

    // MARK: - Backdrop

    /// A deterministic desktop in the theme's mode: Folio's wallpaper gradient (paper
    /// for light themes, ink for dark ones) and a menu bar strip.
    static func backdrop(size: CGSize, scale: CGFloat, appearance: AppTheme.Appearance) -> CGImage? {
        guard let context = FixtureDrawing.makeContext(pointSize: size, scale: scale) else { return nil }
        let isLight = appearance == .light
        let stops: [UInt32] = isLight ? [0xE8DFCF, 0xDCCFB9, 0xCDBDA3] : [0x24211D, 0x1B1916, 0x141210]
        let colors = stops.map { FixturePalette.color(hex: $0).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.52, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width * 0.14, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        // The context's origin is top-left: the menu bar is the first `menuBarHeight` points.
        let menuBar = isLight
            ? NSColor(srgbRed: 246 / 255, green: 242 / 255, blue: 234 / 255, alpha: 0.82)
            : NSColor(srgbRed: 29 / 255, green: 27 / 255, blue: 24 / 255, alpha: 0.78)
        context.setFillColor(menuBar.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: menuBarHeight))
        return context.makeImage()
    }

    // MARK: - Output

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try createParentDirectory(of: url)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw FixtureError(description: "PNG encoding failed")
        }
        try data.write(to: url)
    }

    private static func createParentDirectory(of url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    // MARK: - Keys

    /// ANSI virtual key codes (`kVK_ANSI_*`) of the character keys, by unshifted character.
    nonisolated static let characterKeyCodes: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
    ]

    /// US layout: what Shift types on a non-letter key → the key's unshifted character.
    nonisolated static let shiftedToBase: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
        "~": "`",
    ]

    /// Turns tokens into the events the panel's key monitor would deliver: keyDown and
    /// flagsChanged only (keyUp never reaches `onKeyEvent`), timestamps 30 ms apart.
    /// Modifiers are pressed on their left keys in ⌃⌥⇧⌘fn order and released in reverse;
    /// arrow keyDowns carry `.function` like real ones.
    struct KeyReplay {
        let hyperIncludesShift: Bool
        /// Seconds since an arbitrary epoch.
        private(set) var time: TimeInterval = 1000

        init(hyperIncludesShift: Bool) {
            self.hyperIncludesShift = hyperIncludesShift
        }

        static let eventSpacing: TimeInterval = 0.03

        mutating func pass(milliseconds: Int) {
            time += Double(milliseconds) / 1000
        }

        mutating func events(for token: KeyToken) -> [KeyEvent] {
            switch token {
            case let .press(key, modifiers):
                return press(key, modifiers: modifiers)
            case .record(let spec):
                switch spec {
                case .combo(let combo):
                    return press(combo.key, modifiers: combo.effectiveModifiers(hyperIncludesShift: hyperIncludesShift))
                case .modifierTap(let modifiers):
                    return tap(modifiers.sorted(by: Self.pressOrder))
                case .doubleTap(let modifier):
                    return tap([modifier]) + tap([modifier])
                case .bothSides(let key):
                    let left = Self.physical(SidedModifier(key, side: .left))
                    let right = Self.physical(SidedModifier(key, side: .right))
                    return [
                        flagsChanged(left.code, sides: left.side),
                        flagsChanged(right.code, sides: [left.side, right.side]),
                        flagsChanged(right.code, sides: left.side),
                        flagsChanged(left.code, sides: []),
                    ]
                }
            case .wait:
                return []
            }
        }

        private mutating func press(_ key: KeySpec, modifiers: ModifierSet) -> [KeyEvent] {
            let held = Self.modifierOrder
                .filter { modifiers.contains(Self.modifierSet($0)) }
                .map { Self.physical(SidedModifier($0)) }
            var events: [KeyEvent] = []
            var sides: ModifierSides = []
            for modifier in held {
                sides.insert(modifier.side)
                events.append(flagsChanged(modifier.code, sides: sides))
            }
            events.append(keyDown(key, sides: sides))
            for modifier in held.reversed() {
                sides.remove(modifier.side)
                events.append(flagsChanged(modifier.code, sides: sides))
            }
            return events
        }

        /// Every modifier down in order, then up in reverse, nothing in between.
        private mutating func tap(_ modifiers: [SidedModifier]) -> [KeyEvent] {
            let keys = modifiers.map(Self.physical)
            var events: [KeyEvent] = []
            var sides: ModifierSides = []
            for key in keys {
                sides.insert(key.side)
                events.append(flagsChanged(key.code, sides: sides))
            }
            for key in keys.reversed() {
                sides.remove(key.side)
                events.append(flagsChanged(key.code, sides: sides))
            }
            return events
        }

        private mutating func flagsChanged(_ keyCode: UInt16, sides: ModifierSides) -> KeyEvent {
            time += Self.eventSpacing
            return KeyEvent(kind: .flagsChanged, keyCode: keyCode, modifiers: Self.modifiers(of: sides), sides: sides, timestamp: time)
        }

        private mutating func keyDown(_ key: KeySpec, sides: ModifierSides) -> KeyEvent {
            time += Self.eventSpacing
            var modifiers = Self.modifiers(of: sides)
            let keyCode: UInt16
            let base: String
            let characters: String
            switch key {
            case .named(let named):
                keyCode = named.keyCodes[0]
                base = Self.characters(of: named)
                // ⇧⇥ types backtab.
                characters = named == .tab && modifiers.contains(.shift) ? "\u{19}" : base
                if [.up, .down, .left, .right].contains(named) { modifiers.insert(.function) }
            case .physical(let code):
                keyCode = code
                // What the key types on a US layout, the layout the replay pretends to have.
                base = PhysicalKeyNames.name(forKeyCode: code) ?? ""
                characters = modifiers.contains(.shift) ? (base.first.map(Self.shifted) ?? base) : base
            case .character(let character):
                keyCode = SnapshotCommand.characterKeyCodes[character] ?? 0
                base = String(character)
                characters = modifiers.contains(.shift) ? Self.shifted(character) : base
            }
            return KeyEvent(
                kind: .keyDown,
                keyCode: keyCode,
                modifiers: modifiers,
                sides: sides,
                characters: characters,
                baseCharacters: base,
                timestamp: time
            )
        }

        private static let modifierOrder: [ModifierKey] = [.control, .option, .shift, .command, .function]

        private static func pressOrder(_ lhs: SidedModifier, _ rhs: SidedModifier) -> Bool {
            let left = modifierOrder.firstIndex(of: lhs.key) ?? 0
            let right = modifierOrder.firstIndex(of: rhs.key) ?? 0
            if left != right { return left < right }
            return (KeySide.allCases.firstIndex(of: lhs.side) ?? 0) < (KeySide.allCases.firstIndex(of: rhs.side) ?? 0)
        }

        private static func modifierSet(_ key: ModifierKey) -> ModifierSet {
            switch key {
            case .command: .command
            case .option: .option
            case .control: .control
            case .shift: .shift
            case .function: .function
            }
        }

        /// The physical key for a modifier (`.any` presses the left one) and its key code.
        private static func physical(_ modifier: SidedModifier) -> (code: UInt16, side: ModifierSides) {
            let right = modifier.side == .right
            switch modifier.key {
            case .command: return right ? (0x36, .rightCommand) : (0x37, .leftCommand)
            case .option: return right ? (0x3D, .rightOption) : (0x3A, .leftOption)
            case .control: return right ? (0x3E, .rightControl) : (0x3B, .leftControl)
            case .shift: return right ? (0x3C, .rightShift) : (0x38, .leftShift)
            case .function: return (0x3F, .function)
            }
        }

        private static func modifiers(of sides: ModifierSides) -> ModifierSet {
            var modifiers: ModifierSet = []
            if !sides.isDisjoint(with: [.leftCommand, .rightCommand]) { modifiers.insert(.command) }
            if !sides.isDisjoint(with: [.leftOption, .rightOption]) { modifiers.insert(.option) }
            if !sides.isDisjoint(with: [.leftControl, .rightControl]) { modifiers.insert(.control) }
            if !sides.isDisjoint(with: [.leftShift, .rightShift]) { modifiers.insert(.shift) }
            if sides.contains(.function) { modifiers.insert(.function) }
            return modifiers
        }

        /// What a character key types with Shift on a US keyboard.
        private static func shifted(_ character: Character) -> String {
            if character.isLetter { return character.uppercased() }
            return SnapshotCommand.shiftedToBase.first { $0.value == character }.map { String($0.key) } ?? String(character)
        }

        /// `charactersIgnoringModifiers` of a named key (AppKit's function-key code points).
        private static func characters(of key: NamedKey) -> String {
            let scalar: UInt32
            switch key {
            case .tab: scalar = 0x09
            case .space: scalar = 0x20
            case .return: scalar = 0x0D
            case .escape: scalar = 0x1B
            case .delete: scalar = 0x7F
            case .forwardDelete: scalar = 0xF728
            case .up: scalar = 0xF700
            case .down: scalar = 0xF701
            case .left: scalar = 0xF702
            case .right: scalar = 0xF703
            case .home: scalar = 0xF729
            case .end: scalar = 0xF72B
            case .pageUp: scalar = 0xF72C
            case .pageDown: scalar = 0xF72D
            case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
                 .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
                scalar = 0xF704 + UInt32(Int(key.rawValue.dropFirst()) ?? 1) - 1
            }
            return Unicode.Scalar(scalar).map { String(Character($0)) } ?? ""
        }
    }
}
