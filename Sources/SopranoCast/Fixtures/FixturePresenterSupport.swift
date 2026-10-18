import AppKit
import SopranoCastCore

/// A fixture failure with a message for the command line.
struct FixtureError: Error, CustomStringConvertible {
    var description: String
}

/// The app services `LauncherController` gets in the snapshot harness: a fixed clock that
/// only moves when told to, stored (never fired) scheduled work, fixed usage and history
/// kept in memory, the settings of a `FixtureSettingsStore`, one display.
@MainActor
final class FixturePresenterSupport {
    /// 2026-10-19 12:00 UTC.
    nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_792_411_200)

    /// Chrome, Soprano and Slack were used recently (Root Search's suggestions).
    static let initialUsage: [ItemID: UsageRecord] = {
        func ago(_ hours: Double) -> Date { referenceDate.addingTimeInterval(-hours * 3600) }
        return [
            ItemID(kind: .application, key: "com.google.Chrome"): UsageRecord(uses: [ago(1), ago(5), ago(26), ago(50), ago(120)]),
            ItemID(kind: .application, key: "com.soprano.app"): UsageRecord(uses: [ago(2), ago(30), ago(75)]),
            ItemID(kind: .application, key: "com.tinyspeck.slackmacgap"): UsageRecord(uses: [ago(3), ago(200)]),
        ]
    }()

    /// Past Root Search queries, newest first.
    static let initialHistory = ["slack", "chrome", "left half"]

    /// Upper bound of work items one `advance` may run, so a job that keeps rescheduling
    /// itself at 0 ms cannot hang the harness.
    static let maxWorkPerAdvance = 10_000

    let settingsStore: FixtureSettingsStore
    /// The AppKit visible frame of the one fixture display.
    let visibleFrame: CGRect
    private(set) var usage: [ItemID: UsageRecord] = FixturePresenterSupport.initialUsage
    private(set) var history: [String] = FixturePresenterSupport.initialHistory
    /// Virtual time since `referenceDate`; only `advance(milliseconds:)` moves it.
    private(set) var elapsedMilliseconds = 0

    private struct ScheduledWork {
        var sequence: Int
        var due: Int
        var work: @MainActor () -> Void
    }

    private var pending: [ScheduledWork] = []
    private var nextSequence = 0

    init(settingsStore: FixtureSettingsStore, visibleFrame: CGRect) {
        self.settingsStore = settingsStore
        self.visibleFrame = visibleFrame
    }

    var now: Date { Self.referenceDate.addingTimeInterval(Double(elapsedMilliseconds) / 1000) }

    /// Scheduled work that has not run (or been cancelled) yet.
    var pendingWorkCount: Int { pending.count }

    /// The environment over this support object. `screenFrame` is `visibleFrame` for every
    /// `LauncherScreen` choice; `schedule` stores the work for `advance(milliseconds:)`.
    var environment: LauncherEnvironment {
        LauncherEnvironment(
            settings: { [settingsStore] in settingsStore.settings },
            editSettings: { [settingsStore] edit in try settingsStore.apply(edit) },
            theme: { [settingsStore] in AppTheme.theme(for: settingsStore.settings.theme) },
            now: { self.now },
            schedule: { milliseconds, work in self.schedule(after: milliseconds, work) },
            screenFrame: { _ in self.visibleFrame },
            loadUsage: { self.usage },
            saveUsage: { self.usage = $0 },
            loadHistory: { self.history },
            saveHistory: { self.history = $0 }
        )
    }

    /// Stores `work` to run once `milliseconds` of virtual time have passed; the returned
    /// closure cancels it.
    func schedule(after milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let sequence = nextSequence
        nextSequence += 1
        pending.append(ScheduledWork(sequence: sequence, due: elapsedMilliseconds + max(0, milliseconds), work: work))
        return { [weak self] in
            self?.pending.removeAll { $0.sequence == sequence }
        }
    }

    /// Lets `milliseconds` of virtual time pass: runs every work item that falls due in that
    /// span, in due order (ties in scheduling order), including work scheduled meanwhile.
    func advance(milliseconds: Int) throws {
        let target = elapsedMilliseconds + max(0, milliseconds)
        var ran = 0
        while let next = pending
            .filter({ $0.due <= target })
            .min(by: { ($0.due, $0.sequence) < ($1.due, $1.sequence) })
        {
            ran += 1
            guard ran <= Self.maxWorkPerAdvance else {
                throw FixtureError(description: "scheduled work kept rescheduling itself for \(milliseconds) ms")
            }
            pending.removeAll { $0.sequence == next.sequence }
            elapsedMilliseconds = max(elapsedMilliseconds, next.due)
            next.work()
        }
        elapsedMilliseconds = target
    }
}

/// settings.json in memory: `SettingsEdit`s are applied to the JSONC text with
/// `SettingsEditor` and the result resolved with `SettingsResolver`, like the settings
/// center does with the real file. Every applied edit is recorded.
@MainActor
final class FixtureSettingsStore {
    static let knownThemeIDs = Set(AppTheme.allThemes.map(\.id))

    private(set) var text: String
    private(set) var settings: CastSettings
    private(set) var issues: [ConfigIssue]
    /// `--theme`: replaces the document's theme after every resolve.
    let themeOverride: String?
    /// "set hotkeys.app:com.google.Chrome = \"cmd+2\"", "remove aliases.app:com.apple.mail".
    private(set) var edits: [String] = []
    /// Called after an edit applied, like the settings center's observers (synchronously).
    var onChange: (() -> Void)?

    init(text: String = SettingsTemplate.text, themeOverride: String? = nil) throws {
        let (settings, issues) = try Self.resolve(text, themeOverride: themeOverride)
        self.text = text
        self.settings = settings
        self.issues = issues
        self.themeOverride = themeOverride
    }

    func apply(_ edit: SettingsEdit) throws {
        let edited: String
        let entry: String
        switch edit {
        case let .set(value, path):
            edited = try SettingsEditor.setting(value, at: path, in: text)
            entry = "set \(path.joined(separator: ".")) = \(Self.json(value))"
        case let .remove(path):
            edited = try SettingsEditor.removing(at: path, in: text)
            entry = "remove \(path.joined(separator: "."))"
        }
        let (resolved, issues) = try Self.resolve(edited, themeOverride: themeOverride)
        text = edited
        settings = resolved
        self.issues = issues
        edits.append(entry)
        onChange?()
    }

    static func describe(_ issue: ConfigIssue) -> String {
        issue.line.map { "line \($0): \(issue.message)" } ?? issue.message
    }

    private static func resolve(_ text: String, themeOverride: String?) throws -> (CastSettings, [ConfigIssue]) {
        let resolution = SettingsResolver.resolve(text: text, knownThemeIDs: knownThemeIDs)
        guard var settings = resolution.settings else {
            throw FixtureError(description: resolution.issues.map(describe).joined(separator: "; "))
        }
        if let themeOverride { settings.theme = themeOverride }
        return (settings, resolution.issues)
    }

    /// Compact JSON with sorted keys; `String(describing:)` for values JSON can't hold.
    private static func json(_ value: Any) -> String {
        let wrapped: [Any] = [value]
        guard JSONSerialization.isValidJSONObject(wrapped),
              let data = try? JSONSerialization.data(withJSONObject: wrapped, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return String(describing: value) }
        // "[value]" → "value".
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}

/// Forwards everything to the real presenter and remembers the last view model, so the
/// harness knows which text field has focus and what it holds (keys the launcher doesn't
/// consume are typed into that field, like the panel's text fields would).
@MainActor
final class ModelRecordingPresenter: LauncherPresenting {
    let inner: any LauncherPresenting
    private(set) var lastModel: LauncherViewModel?

    init(_ inner: any LauncherPresenting) {
        self.inner = inner
    }

    var isPresented: Bool { inner.isPresented }
    var visibleRowCount: Int { inner.visibleRowCount }

    func present(_ model: LauncherViewModel, screenFrame: CGRect) {
        lastModel = model
        inner.present(model, screenFrame: screenFrame)
    }

    func update(_ model: LauncherViewModel) {
        lastModel = model
        inner.update(model)
    }

    func dismiss() {
        inner.dismiss()
    }

    func showHUD(_ text: String, screenFrame: CGRect) {
        inner.showHUD(text, screenFrame: screenFrame)
    }

    var onKeyEvent: ((KeyEvent) -> Bool)? {
        get { inner.onKeyEvent }
        set { inner.onKeyEvent = newValue }
    }

    var onQueryChange: ((String) -> Void)? {
        get { inner.onQueryChange }
        set { inner.onQueryChange = newValue }
    }

    var onArgumentChange: ((Int, String) -> Void)? {
        get { inner.onArgumentChange }
        set { inner.onArgumentChange = newValue }
    }

    var onOverlayTextChange: ((String) -> Void)? {
        get { inner.onOverlayTextChange }
        set { inner.onOverlayTextChange = newValue }
    }

    var onRowClick: ((Int, Int) -> Void)? {
        get { inner.onRowClick }
        set { inner.onRowClick = newValue }
    }

    var onActionClick: ((Int) -> Void)? {
        get { inner.onActionClick }
        set { inner.onActionClick = newValue }
    }

    var onResignKey: (() -> Void)? {
        get { inner.onResignKey }
        set { inner.onResignKey = newValue }
    }

    func renderSnapshot(screenFrame: CGRect, scale: CGFloat, backdrop: CGImage?) -> CGImage? {
        inner.renderSnapshot(screenFrame: screenFrame, scale: scale, backdrop: backdrop)
    }

    /// The focused text field's text and the callback reporting a new text for it; nil
    /// when no text field has focus (recorder, output, confirmation, a dropdown argument).
    func focusedField() -> (text: String, change: (String) -> Void)? {
        guard let model = lastModel else { return nil }
        switch model.focus {
        case .query:
            return (model.query, { [weak self] in self?.onQueryChange?($0) })
        case .argument(let index):
            guard model.arguments.indices.contains(index), model.arguments[index].options == nil else { return nil }
            return (model.arguments[index].value, { [weak self] in self?.onArgumentChange?(index, $0) })
        case .overlay:
            let text: String
            switch model.overlay {
            case let .actionPanel(_, query, _, _): text = query
            case let .aliasEditor(_, aliasText, _): text = aliasText
            default: return nil
            }
            return (text, { [weak self] in self?.onOverlayTextChange?($0) })
        case .none:
            return nil
        }
    }
}
