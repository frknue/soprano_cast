import AppKit
@testable import SopranoCast
@testable import SopranoCastCore

/// A presenter that draws nothing and remembers what the controller asked for.
@MainActor
final class RecordingPresenter: LauncherPresenting {
    private(set) var isPresented = false
    var visibleRowCount = 8
    /// The last model presented or updated.
    private(set) var model: LauncherViewModel?
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var screenFrames: [CGRect] = []
    private(set) var huds: [String] = []

    var onKeyEvent: ((KeyEvent) -> Bool)?
    var onQueryChange: ((String) -> Void)?
    var onArgumentChange: ((Int, String) -> Void)?
    var onOverlayTextChange: ((String) -> Void)?
    var onRowClick: ((Int, Int) -> Void)?
    var onActionClick: ((Int) -> Void)?
    var onResignKey: (() -> Void)?

    func present(_ model: LauncherViewModel, screenFrame: CGRect) {
        isPresented = true
        self.model = model
        screenFrames.append(screenFrame)
        presentCount += 1
    }

    func update(_ model: LauncherViewModel) {
        self.model = model
    }

    func dismiss() {
        isPresented = false
        dismissCount += 1
    }

    func showHUD(_ text: String, screenFrame: CGRect) {
        huds.append(text)
    }

    /// Nothing is drawn, so there is nothing to render.
    func renderSnapshot(screenFrame: CGRect, scale: CGFloat, backdrop: CGImage?) -> CGImage? {
        nil
    }
}

/// A fixed list of items.
@MainActor
final class StubSource: ItemSource {
    var items: [CastItem]
    var onChange: (() -> Void)?

    init(items: [CastItem]) {
        self.items = items
    }

    func start() {}
    func stop() {}
}

/// Plain images; nothing loads later.
@MainActor
final class StubIcons: IconProviding {
    var onLoad: (() -> Void)?

    func image(for icon: ItemIcon, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size))
    }
}

/// Records runs and actions and answers with scripted outcomes.
@MainActor
final class StubRunner: ItemRunning {
    struct Run: Equatable {
        var id: ItemID
        var arguments: [String]
    }

    struct Action: Equatable {
        var action: ItemActionID
        var id: ItemID
    }

    private(set) var runs: [Run] = []
    private(set) var actions: [Action] = []
    /// Per item; unlisted items finish with `.done(closeLauncher: true)`.
    var outcomes: [ItemID: RunOutcome] = [:]
    var actionOutcome: RunOutcome = .hud("Copied")
    var runningIDs: Set<ItemID> = []
    var frontmostIDs: Set<ItemID> = []

    func run(_ item: CastItem, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void) {
        runs.append(Run(id: item.id, arguments: arguments))
        completion(outcomes[item.id] ?? .done(closeLauncher: true))
    }

    func perform(_ action: ItemActionID, on item: CastItem) -> RunOutcome {
        actions.append(Action(action: action, id: item.id))
        return actionOutcome
    }

    func isRunning(_ item: CastItem) -> Bool {
        runningIDs.contains(item.id)
    }

    func isFrontmost(_ item: CastItem) -> Bool {
        frontmostIDs.contains(item.id)
    }
}

/// Records suspend/resume; registers nothing.
@MainActor
final class StubHotkeys: HotkeyRegistering {
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0
    var onTrigger: ((HotkeyTarget) -> Void)?

    func setBindings(_ bindings: [HotkeyBinding], hyperKey: HyperKeySettings) -> [HotkeyFailure] {
        []
    }

    func suspend() { suspendCount += 1 }
    func resume() { resumeCount += 1 }
}

/// Holds scheduled work until a test fires it; cancelled work never runs.
@MainActor
final class ManualScheduler {
    private final class Entry {
        let milliseconds: Int
        let work: @MainActor () -> Void
        var isCancelled = false

        init(milliseconds: Int, work: @escaping @MainActor () -> Void) {
            self.milliseconds = milliseconds
            self.work = work
        }
    }

    private var entries: [Entry] = []

    /// Delays of the work still waiting, in scheduling order.
    var pendingDelays: [Int] {
        entries.filter { !$0.isCancelled }.map { $0.milliseconds }
    }

    func schedule(_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let entry = Entry(milliseconds: milliseconds, work: work)
        entries.append(entry)
        return { entry.isCancelled = true }
    }

    /// Runs every pending, uncancelled piece of work (work scheduled meanwhile waits).
    func fireAll() {
        let due = entries
        entries = []
        for entry in due where !entry.isCancelled {
            entry.work()
        }
    }

    /// Runs only the pending work scheduled with `milliseconds`.
    func fire(milliseconds: Int) {
        let due = entries.filter { $0.milliseconds == milliseconds }
        entries.removeAll { $0.milliseconds == milliseconds }
        for entry in due where !entry.isCancelled {
            entry.work()
        }
    }
}

/// The items the launcher tests search.
enum LauncherTestItems {
    static let chrome = CastItem(
        id: ItemID(rawValue: "app:com.google.Chrome"), title: "Google Chrome", subtitle: "/Applications",
        icon: .file(path: "/Applications/Google Chrome.app")
    )
    static let slack = CastItem(
        id: ItemID(rawValue: "app:com.tinyspeck.slackmacgap"), title: "Slack", subtitle: "/Applications",
        icon: .file(path: "/Applications/Slack.app")
    )
    static let notes = CastItem(
        id: ItemID(rawValue: "app:com.apple.Notes"), title: "Notes", subtitle: "/System/Applications",
        icon: .file(path: "/System/Applications/Notes.app")
    )
    /// A script with one required argument.
    static let greet = CastItem(
        id: ItemID(rawValue: "script:/scripts/greet.sh"), title: "Greet", subtitle: "Demo",
        icon: .emoji("👋"), arguments: [ArgumentSpec(name: "name", placeholder: "Name")]
    )
    /// A script that asks before it runs.
    static let deploy = CastItem(
        id: ItemID(rawValue: "script:/scripts/deploy.sh"), title: "Deploy Site", subtitle: "Ops",
        icon: .emoji("🚀"), needsConfirmation: true
    )

    static let all = [chrome, slack, notes, greet, deploy]
    static let searchGoogle = ItemID(kind: .castCommand, key: CastCommand.searchGoogle.rawValue)
}

/// A `LauncherController` on stub items with a recording presenter, stub runner and hotkeys,
/// a manual scheduler and in-memory settings, usage and history. `editSettings` applies each
/// edit to the settings value and calls `settingsDidChange`, like the settings center.
@MainActor
final class LauncherHarness {
    private final class State {
        var settings: CastSettings
        var now: Date
        var edits: [String] = []
        var savedUsage: [ItemID: UsageRecord] = [:]
        var savedHistory: [String] = []
        weak var controller: LauncherController?

        init(settings: CastSettings, now: Date) {
            self.settings = settings
            self.now = now
        }
    }

    struct EditError: Error {}

    static let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 949)

    let source: StubSource
    let runner: StubRunner
    let presenter: RecordingPresenter
    let hotkeys: StubHotkeys
    let scheduler: ManualScheduler
    let controller: LauncherController
    private let state: State

    init(
        items: [CastItem] = LauncherTestItems.all,
        settings: CastSettings = CastSettings(),
        history: [String] = [],
        usage: [ItemID: UsageRecord] = [:]
    ) {
        let source = StubSource(items: items)
        let runner = StubRunner()
        let presenter = RecordingPresenter()
        let hotkeys = StubHotkeys()
        let scheduler = ManualScheduler()
        let state = State(settings: settings, now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let environment = LauncherEnvironment(
            settings: { state.settings },
            editSettings: { edit in
                try LauncherHarness.apply(edit, to: &state.settings, log: &state.edits)
                state.controller?.settingsDidChange()
            },
            theme: { AppTheme.folioPaper },
            now: { state.now },
            schedule: { milliseconds, work in scheduler.schedule(milliseconds, work) },
            screenFrame: { _ in LauncherHarness.screenFrame },
            loadUsage: { usage },
            saveUsage: { state.savedUsage = $0 },
            loadHistory: { history },
            saveHistory: { state.savedHistory = $0 }
        )
        self.source = source
        self.runner = runner
        self.presenter = presenter
        self.hotkeys = hotkeys
        self.scheduler = scheduler
        self.state = state
        controller = LauncherController(
            sources: [source], icons: StubIcons(), runner: runner, presenter: presenter,
            hotkeys: hotkeys, environment: environment, keyCode: LauncherHarness.usKeyCode
        )
        state.controller = controller
    }

    /// A fixed US layout for the characters the tests use, so conflicts between character
    /// and physical hotkeys don't depend on the machine's input source.
    nonisolated static func usKeyCode(_ key: KeySpec) -> UInt16? {
        switch key {
        case .physical(let code): code
        case .named(let named): named.keyCodes.first
        case .character(let character): keyCodes[character]
        }
    }

    /// Changing settings takes effect through `controller.settingsDidChange()`.
    var settings: CastSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    var now: Date {
        get { state.now }
        set { state.now = newValue }
    }

    /// "set hotkeys.<id> = <text>", "remove aliases.<id>", "set favorites = a, b".
    var edits: [String] { state.edits }
    var savedUsage: [ItemID: UsageRecord] { state.savedUsage }
    var savedHistory: [String] { state.savedHistory }

    var model: LauncherViewModel? { presenter.model }
    var snapshot: LauncherStateSnapshot { controller.state }

    // MARK: Typing

    func type(_ text: String) {
        presenter.onQueryChange?(text)
    }

    /// One named key down; returns whether it was handled.
    @discardableResult
    func press(_ key: NamedKey, _ modifiers: ModifierSet = []) -> Bool {
        presenter.onKeyEvent?(KeyEvent(kind: .keyDown, keyCode: key.keyCodes[0], modifiers: modifiers)) ?? false
    }

    /// One character key down (as typed with no modifiers); returns whether it was handled.
    @discardableResult
    func press(character: Character, _ modifiers: ModifierSet = []) -> Bool {
        let text = String(character)
        let event = KeyEvent(
            kind: .keyDown, keyCode: Self.keyCodes[character] ?? 0, modifiers: modifiers,
            characters: text, baseCharacters: text
        )
        return presenter.onKeyEvent?(event) ?? false
    }

    /// Plays ⇧⌘K into the recorder like a person: ⌘ down, ⇧ down, K down/up, ⇧ up, ⌘ up.
    func recordShiftCommandK() {
        flags([.command], [.leftCommand])
        flags([.shift, .command], [.leftCommand, .leftShift])
        _ = presenter.onKeyEvent?(KeyEvent(
            kind: .keyDown, keyCode: 0x28, modifiers: [.shift, .command], characters: "K", baseCharacters: "k"
        ))
        _ = presenter.onKeyEvent?(KeyEvent(kind: .keyUp, keyCode: 0x28, modifiers: [.shift, .command]))
        flags([.command], [.leftCommand])
        flags([], [])
    }

    /// Plays ⌘Space into the recorder.
    func recordCommandSpace() {
        flags([.command], [.leftCommand])
        _ = presenter.onKeyEvent?(KeyEvent(
            kind: .keyDown, keyCode: NamedKey.space.keyCodes[0], modifiers: [.command], characters: " ", baseCharacters: " "
        ))
        flags([], [])
    }

    func flags(_ modifiers: ModifierSet, _ sides: ModifierSides) {
        _ = presenter.onKeyEvent?(KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: modifiers, sides: sides))
    }

    /// The overlay as drawn.
    var overlayModel: OverlayViewModel? { presenter.model?.overlay }

    var actionTitles: [String] {
        guard case .actionPanel(_, _, let rows, _)? = overlayModel else { return [] }
        return rows.map { $0.title }
    }

    /// ANSI virtual key codes of the characters the tests type.
    nonisolated private static let keyCodes: [Character: UInt16] = [
        "k": 0x28, "f": 0x03, ",": 0x2B, "w": 0x0D, "o": 0x1F, "c": 0x08, "d": 0x02,
    ]

    // MARK: Settings edits

    /// Applies one launcher edit to `settings` and logs it.
    static func apply(_ edit: SettingsEdit, to settings: inout CastSettings, log: inout [String]) throws {
        switch edit {
        case .set(let value, let path):
            switch (path.first, path.count) {
            case ("hotkeys"?, 2):
                guard let text = value as? String, let spec = HotkeySpec(settingsText: text) else { throw EditError() }
                settings.hotkeys[ItemID(rawValue: path[1])] = spec
                log.append("set hotkeys.\(path[1]) = \(text)")
            case ("aliases"?, 2):
                guard let text = value as? String else { throw EditError() }
                settings.aliases[ItemID(rawValue: path[1])] = text
                log.append("set aliases.\(path[1]) = \(text)")
            case ("favorites"?, 1):
                guard let ids = value as? [String] else { throw EditError() }
                settings.favorites = ids.map(ItemID.init(rawValue:))
                log.append("set favorites = \(ids.joined(separator: ", "))")
            case ("disabled"?, 1):
                guard let ids = value as? [String] else { throw EditError() }
                settings.disabled = Set(ids.map(ItemID.init(rawValue:)))
                log.append("set disabled = \(ids.joined(separator: ", "))")
            default:
                throw EditError()
            }
        case .remove(let path):
            switch (path.first, path.count) {
            case ("hotkeys"?, 2):
                settings.hotkeys[ItemID(rawValue: path[1])] = nil
            case ("aliases"?, 2):
                settings.aliases[ItemID(rawValue: path[1])] = nil
            default:
                throw EditError()
            }
            log.append("remove \(path.joined(separator: "."))")
        case .quicklink:
            // The launcher never writes quicklinks.
            throw EditError()
        }
    }
}
