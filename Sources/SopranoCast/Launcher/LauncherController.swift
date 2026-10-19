import AppKit
import SopranoCastCore

/// The launcher's state as the snapshot harness and the tests see it.
struct LauncherStateSnapshot: Equatable {
    var query: String
    var selectedID: ItemID?
    /// Every row, flat over the sections.
    var rowIDs: [ItemID]
    /// "none", "actionPanel", "configureCommand", "recorder", "aliasEditor", "output",
    /// "confirmation".
    var overlay: String
    var argumentValues: [String]
    var footerToast: String?
}

/// Root Search's state machine: ranks the items for the query, turns keys into
/// `LauncherCommand`s, runs items and their actions, writes favorites, hotkeys, aliases and
/// disabled items to settings.json, and keeps the presenter drawing the current
/// `LauncherViewModel`. Everything outside it (items, icons, running, drawing, hotkeys,
/// settings, timing, persistence) comes in through protocols and `LauncherEnvironment`, so
/// the tests and the snapshot harness run it on fixtures.
@MainActor
final class LauncherController {
    /// How long a footer toast stays.
    static let toastMilliseconds = 3000
    /// A recorded hotkey saves itself after this long.
    static let recorderCountdownMilliseconds = 1500
    /// The countdown bar advances this often.
    static let recorderTickMilliseconds = 100

    /// The key code `key` sits on: physical keys their own, named keys their canonical code,
    /// character keys the one typing that character on the current layout (main thread).
    nonisolated static func layoutKeyCode(_ key: KeySpec) -> UInt16? {
        switch key {
        case .physical(let code): code
        case .named(let named): named.keyCodes.first
        case .character(let character): KeyboardLayout.keyCode(for: character)
        }
    }

    private let sources: [ItemSource]
    private let icons: IconProviding
    private let runner: ItemRunning
    private let presenter: LauncherPresenting
    private let hotkeys: HotkeyRegistering
    private let environment: LauncherEnvironment
    /// The virtual key code a hotkey key sits on, for conflicts between character and
    /// physical hotkeys; the current keyboard layout's by default (tests pass a fixed one).
    private let keyCode: (KeySpec) -> UInt16?

    /// Reloaded from `environment.settings()` by `settingsDidChange`.
    private var settings: CastSettings
    /// Every item Root Search can list right now (sources + `BuiltinItems`), for the CLI.
    private(set) var allItems: [CastItem] = []
    private var itemsByID: [ItemID: CastItem] = [:]
    private var usage: [ItemID: UsageRecord]
    private var history: SearchHistory
    /// The query typed before ↑ stepped into the history; ↓ past the newest entry restores it.
    private var queryBeforeHistory: String?

    private var query = ""
    private var sections: [ResultSection] = []
    private var selectedIndex: Int?
    /// A hotkey or the CLI opened the launcher on this item (it lacked arguments or needs
    /// confirmation): the list shows it alone until the query changes.
    private var pinnedItemID: ItemID?
    /// The item `argumentValues` belong to; values reset when the selection moves on.
    private var argumentItemID: ItemID?
    private var argumentValues: [String] = []
    private var focus: LauncherFocus = .query
    private var overlay: Overlay = .none
    private var toast: LauncherToast?
    private var cancelToast: (() -> Void)?
    private var cancelCountdown: (() -> Void)?
    private var cancelCountdownTick: (() -> Void)?
    /// When the launcher was last hidden, for pop-to-root.
    private var hiddenAt: Date?
    /// The visible frame the panel was last presented on.
    private var presentedScreenFrame: CGRect?

    init(
        sources: [ItemSource],
        icons: IconProviding,
        runner: ItemRunning,
        presenter: LauncherPresenting,
        hotkeys: HotkeyRegistering,
        environment: LauncherEnvironment,
        keyCode: @escaping (KeySpec) -> UInt16? = LauncherController.layoutKeyCode
    ) {
        self.sources = sources
        self.icons = icons
        self.runner = runner
        self.presenter = presenter
        self.hotkeys = hotkeys
        self.environment = environment
        self.keyCode = keyCode
        settings = environment.settings()
        usage = environment.loadUsage()
        history = SearchHistory(entries: environment.loadHistory())
        rebuildItems()
        rank(resetSelection: true)

        for source in sources {
            source.onChange = { [weak self] in self?.sourcesDidChange() }
        }
        icons.onLoad = { [weak self] in self?.render() }
        presenter.onKeyEvent = { [weak self] event in self?.handleKeyEvent(event) ?? false }
        presenter.onQueryChange = { [weak self] text in self?.queryDidChange(text) }
        presenter.onArgumentChange = { [weak self] index, text in self?.argumentDidChange(index, text) }
        presenter.onOverlayTextChange = { [weak self] text in self?.overlayTextDidChange(text) }
        presenter.onRowClick = { [weak self] index, clicks in self?.rowClicked(index, clickCount: clicks) }
        presenter.onActionClick = { [weak self] index in self?.actionClicked(index) }
        presenter.onResignKey = { [weak self] in self?.resignedKey() }
    }

    var isVisible: Bool { presenter.isPresented }

    // MARK: - Showing

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Opens on the display `launcher.screen` picks. Reopening later than
    /// `popToRootSeconds` after hiding starts from Root Search; sooner, everything is as left.
    func show() {
        guard !isVisible else {
            render()
            return
        }
        if let hiddenAt, shouldPopToRoot(hiddenAt: hiddenAt) {
            resetToRoot()
        }
        hiddenAt = nil
        rank(resetSelection: false)
        presentPanel()
    }

    /// Closes the window; overlays and toasts go, the query, selection and arguments stay.
    func hide() {
        guard isVisible else { return }
        setOverlay(.none)
        clearToast()
        history.resetCursor()
        queryBeforeHistory = nil
        presenter.dismiss()
        hiddenAt = environment.now()
    }

    /// A hotkey or the CLI: runs the item without showing the launcher. An item with
    /// required arguments missing opens the launcher on it with the first missing argument
    /// focused; one that needs confirmation opens the launcher on its confirmation.
    func run(itemID: ItemID, arguments: [String]) {
        guard let item = itemsByID[itemID] else {
            presenter.showHUD("No command \(itemID.rawValue)", screenFrame: hudScreenFrame)
            return
        }
        let values = Self.filled(arguments, for: item.arguments)
        if let missing = Self.firstMissingArgument(item.arguments, values: values) {
            openPinned(item, values: values, focus: .argument(missing))
        } else if item.needsConfirmation {
            openPinned(item, values: values, focus: .query)
            setOverlay(.confirmation(PendingRun(item: item, arguments: values, recordsQuery: false)))
            render()
        } else {
            execute(item, arguments: values, recordsQuery: false)
        }
    }

    /// An item's hotkey: `run(itemID:arguments: [])`, except that an application already in
    /// front with a window on screen is hidden instead, as in Raycast.
    func runHotkey(itemID: ItemID) {
        if let item = itemsByID[itemID], item.kind == .application, runner.isFrontmost(item) {
            present(runner.perform(.hideApplication, on: item))
            return
        }
        run(itemID: itemID, arguments: [])
    }

    /// Settings or the theme changed: reloads settings, rebuilds the items and the ranking
    /// (keeping the selection) and redraws.
    func settingsDidChange() {
        settings = environment.settings()
        rebuildItems()
        validateOverlay()
        rank(resetSelection: false)
        render()
    }

    var state: LauncherStateSnapshot {
        LauncherStateSnapshot(
            query: query,
            selectedID: selectedRow?.ranked.item.id,
            rowIDs: flatRows.map { $0.ranked.item.id },
            overlay: overlay.name,
            argumentValues: argumentValues,
            footerToast: toast?.text
        )
    }

    // MARK: - Input

    /// Every keyDown/flagsChanged while the panel is key; true when handled. The recorder
    /// takes every event; otherwise `LauncherKeyRouter` decides.
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        if case .recorder = overlay {
            recorderDidReceive(event)
            return true
        }
        guard let command = LauncherKeyRouter.command(for: event, input: routerInput) else { return false }
        perform(command)
        return true
    }

    private var routerInput: RouterInput {
        let count = flatRows.count
        return RouterInput(
            context: overlay.context(focus: focus),
            navigation: settings.launcher.navigation,
            selectionAtTop: selectedIndex == nil || selectedIndex == 0,
            selectionAtBottom: selectedIndex == nil || selectedIndex == count - 1,
            selectionHasArguments: !selectionArguments.isEmpty
        )
    }

    private func perform(_ command: LauncherCommand) {
        switch command {
        case .moveUp, .moveDown, .pageUp, .pageDown, .sectionUp, .sectionDown:
            move(command)
        case .historyPrevious:
            historyPrevious()
        case .historyNext:
            historyNext()
        case .runPrimary:
            runPrimary()
        case .runSecondary:
            if let item = actionTarget, let action = ItemActions.secondary(for: item) {
                perform(action.id, on: item)
            }
        case .runTertiary:
            if let item = actionTarget, let action = ItemActions.tertiary(for: item) {
                perform(action.id, on: item)
            }
        case .toggleActionPanel:
            toggleActionPanel()
        case .configureCommand:
            openConfigureCommand()
        case .toggleFavorite:
            runShortcut(.toggleFavorite)
        case .moveFavoriteUp:
            runShortcut(.moveFavoriteUp)
        case .moveFavoriteDown:
            runShortcut(.moveFavoriteDown)
        case .disableCommand:
            runShortcut(.disableCommand)
        case .runAction(let id):
            runShortcut(id)
        case .back:
            back()
        case .popToRoot:
            resetToRoot()
            render()
        case .closeWindow:
            hide()
        case .openSettings:
            openSettings()
        case .nextArgument:
            cycleArgumentFocus(by: 1)
        case .previousArgument:
            cycleArgumentFocus(by: -1)
        }
    }

    private func queryDidChange(_ text: String) {
        guard text != query else { return }
        history.resetCursor()
        queryBeforeHistory = nil
        pinnedItemID = nil
        focus = .query
        if text.hasSuffix(" "), focusArgumentsForAlias(String(text.dropLast())) {
            render()
            return
        }
        query = text
        rank(resetSelection: true)
        render()
    }

    /// Typing an alias followed by a space selects its item and focuses its first argument
    /// (Raycast). The query keeps the alias without the space. False when `text` is no
    /// alias of a listed item with arguments.
    private func focusArgumentsForAlias(_ text: String) -> Bool {
        let alias = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !alias.isEmpty, settings.aliases.values.contains(alias) else { return false }
        query = text
        rank(resetSelection: true)
        guard let index = flatRows.firstIndex(where: { row in
            row.kind != .fallbacks && !row.ranked.item.arguments.isEmpty && settings.aliases[row.ranked.item.id] == alias
        }) else { return false }
        selectedIndex = index
        syncArguments()
        focus = .argument(0)
        return true
    }

    private func argumentDidChange(_ index: Int, _ text: String) {
        let specs = selectionArguments
        guard specs.indices.contains(index) else { return }
        argumentValues = Self.filled(argumentValues, for: specs)
        argumentValues[index] = Self.value(text, for: specs[index])
        focus = .argument(index)
        render()
    }

    private func overlayTextDidChange(_ text: String) {
        switch overlay {
        case .actionPanel(var panel):
            panel.query = text
            panel.selectedIndex = filteredActions(panel).isEmpty ? nil : 0
            overlay = .actionPanel(panel)
        case .aliasEditor(var editor):
            editor.text = text.lowercased()
            editor.error = Self.isValidAlias(editor.text) ? nil : Self.aliasCharactersError
            overlay = .aliasEditor(editor)
        case .none, .recorder, .output, .confirmation:
            return
        }
        render()
    }

    /// One click selects a row; a double click runs it.
    private func rowClicked(_ index: Int, clickCount: Int) {
        guard case .none = overlay, flatRows.indices.contains(index) else { return }
        selectedIndex = index
        syncArguments()
        if clickCount >= 2 {
            runSelection()
        }
        render()
    }

    private func actionClicked(_ index: Int) {
        guard case .actionPanel(var panel) = overlay, filteredActions(panel).indices.contains(index) else { return }
        panel.selectedIndex = index
        overlay = .actionPanel(panel)
        runSelectedAction(panel)
    }

    private func resignedKey() {
        if settings.launcher.closeOnFocusLoss {
            hide()
        }
    }

    // MARK: - Navigation

    private func move(_ command: LauncherCommand) {
        let pageSize = max(presenter.visibleRowCount, 1)
        switch overlay {
        case .none:
            selectedIndex = ResultNavigator.move(
                command, selected: selectedIndex, rowCounts: sections.map(\.rows.count), pageSize: pageSize
            )
            syncArguments()
        case .actionPanel(var panel):
            let count = filteredActions(panel).count
            panel.selectedIndex = ResultNavigator.move(command, selected: panel.selectedIndex, rowCounts: [count], pageSize: pageSize)
            overlay = .actionPanel(panel)
        case .recorder, .aliasEditor, .output, .confirmation:
            return
        }
        render()
    }

    /// ↑ at the top of the list: the next older query from the history.
    private func historyPrevious() {
        guard let entry = history.previous(currentQuery: query) else { return }
        if queryBeforeHistory == nil {
            queryBeforeHistory = query
        }
        showHistoryQuery(entry)
    }

    /// ↓ at the bottom while browsing the history: the next newer query, then the typed one.
    private func historyNext() {
        guard let typed = queryBeforeHistory else { return }
        if let entry = history.next() {
            showHistoryQuery(entry)
        } else {
            queryBeforeHistory = nil
            showHistoryQuery(typed)
        }
    }

    private func showHistoryQuery(_ text: String) {
        pinnedItemID = nil
        query = text
        focus = .query
        rank(resetSelection: true)
        render()
    }

    /// Tab / ⇧Tab: query → argument 1 → … → query.
    private func cycleArgumentFocus(by step: Int) {
        let count = selectionArguments.count
        let positions = count + 1
        let current: Int
        if case .argument(let index) = focus, index < count {
            current = index + 1
        } else {
            current = 0
        }
        let next = ((current + step) % positions + positions) % positions
        focus = next == 0 ? .query : .argument(next - 1)
        render()
    }

    /// Esc: closes the topmost overlay; with none, the window.
    private func back() {
        guard !overlay.isNone else {
            hide()
            return
        }
        setOverlay(.none)
        render()
    }

    /// Clears the query, the arguments, every overlay and the selection.
    private func resetToRoot() {
        setOverlay(.none)
        pinnedItemID = nil
        query = ""
        argumentItemID = nil
        argumentValues = []
        focus = .query
        history.resetCursor()
        queryBeforeHistory = nil
        rank(resetSelection: true)
    }

    private func shouldPopToRoot(hiddenAt: Date) -> Bool {
        let seconds = settings.launcher.popToRootSeconds
        return seconds == 0 || environment.now().timeIntervalSince(hiddenAt) > TimeInterval(seconds)
    }

    // MARK: - Running

    private func runPrimary() {
        switch overlay {
        case .none:
            runSelection()
        case .actionPanel(let panel):
            runSelectedAction(panel)
        case .aliasEditor:
            saveAlias()
        case .confirmation(let pending):
            setOverlay(.none)
            render()
            execute(pending.item, arguments: pending.arguments, recordsQuery: pending.recordsQuery)
        case .output:
            setOverlay(.none)
            render()
        case .recorder:
            return
        }
    }

    /// The selected row's primary action. Fallback rows run with the query as their first
    /// argument; an empty required argument gets focus first (a toast when it already has
    /// it); `needsConfirmation` asks first.
    private func runSelection() {
        guard let row = selectedRow else { return }
        let item = row.ranked.item
        if row.kind == .fallbacks {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let arguments = item.arguments.isEmpty ? [] : Self.filled([text], for: item.arguments)
            start(item, arguments: arguments)
            return
        }
        let values = Self.filled(argumentValues, for: item.arguments)
        if let missing = Self.firstMissingArgument(item.arguments, values: values) {
            if focus == .argument(missing) {
                showToast("Fill in \(item.arguments[missing].name)", isError: false)
            } else {
                focus = .argument(missing)
                render()
            }
            return
        }
        start(item, arguments: values)
    }

    /// Runs `item` from Root Search, asking first when it needs confirmation.
    private func start(_ item: CastItem, arguments: [String]) {
        if item.needsConfirmation {
            setOverlay(.confirmation(PendingRun(item: item, arguments: arguments, recordsQuery: true)))
            render()
        } else {
            execute(item, arguments: arguments, recordsQuery: true)
        }
    }

    /// Records usage (and the query in the search history when run from Root Search),
    /// runs, and presents the outcome when it arrives.
    private func execute(_ item: CastItem, arguments: [String], recordsQuery: Bool) {
        if item.id != .calculatorResult {
            usage[item.id] = Frecency.recording(environment.now(), in: usage[item.id])
            environment.saveUsage(usage)
        }
        if recordsQuery {
            history.record(query)
            environment.saveHistory(history.entries)
            queryBeforeHistory = nil
        }
        runner.run(item, arguments: arguments) { [weak self] outcome in
            self?.present(outcome)
        }
    }

    private func openSettings() {
        let id = ItemID(kind: .castCommand, key: CastCommand.openSettings.rawValue)
        guard let item = itemsByID[id] else { return }
        runner.run(item, arguments: []) { [weak self] outcome in
            self?.present(outcome)
        }
    }

    /// `.done` closes when asked; `.hud` closes and shows the HUD; `.toast` shows in the
    /// footer (a HUD when the launcher is hidden); `.output` opens the output view.
    private func present(_ outcome: RunOutcome) {
        switch outcome {
        case .done(let closeLauncher):
            if closeLauncher {
                closeAfterRun()
            }
        case .hud(let text):
            let frame = hudScreenFrame
            closeAfterRun()
            presenter.showHUD(text, screenFrame: frame)
        case .toast(let text, let isError):
            if isVisible {
                showToast(text, isError: isError)
            } else {
                presenter.showHUD(text, screenFrame: hudScreenFrame)
            }
        case .output(let title, let text, let isError):
            if !isVisible {
                show()
            }
            setOverlay(.output(title: title, text: text, isError: isError))
            render()
        }
    }

    /// After a run Raycast closes and starts the next search from Root Search.
    private func closeAfterRun() {
        guard isVisible else { return }
        hide()
        resetToRoot()
    }

    /// The display the HUD appears on: the launcher's while it is (or was just) shown.
    private var hudScreenFrame: CGRect {
        if isVisible, let presentedScreenFrame {
            return presentedScreenFrame
        }
        return environment.screenFrame(settings.launcher.screen)
    }

    /// Opens the launcher (or redraws it) with `item` as the only row and its arguments.
    private func openPinned(_ item: CastItem, values: [String], focus newFocus: LauncherFocus) {
        setOverlay(.none)
        clearToast()
        pinnedItemID = item.id
        query = ""
        history.resetCursor()
        queryBeforeHistory = nil
        rank(resetSelection: true)
        argumentValues = values
        focus = newFocus
        hiddenAt = nil
        if isVisible {
            render()
        } else {
            presentPanel()
        }
    }

    // MARK: - Actions

    /// The item the actions apply to: the Action Panel's, else the selection.
    private var actionTarget: CastItem? {
        if case .actionPanel(let panel) = overlay {
            return panel.item
        }
        return selectedRow?.ranked.item
    }

    private func itemActions(for item: CastItem) -> [ItemAction] {
        let favorites = settings.favorites
        let index = favorites.firstIndex(of: item.id)
        return ItemActions.actions(
            for: item,
            isRunning: item.kind == .application && runner.isRunning(item),
            isFavorite: index != nil,
            canMoveFavoriteUp: index.map { $0 > 0 } ?? false,
            canMoveFavoriteDown: index.map { $0 < favorites.count - 1 } ?? false,
            hasHotkey: settings.hotkeys[item.id] != nil,
            hasAlias: settings.aliases[item.id] != nil
        )
    }

    private func filteredActions(_ panel: ActionPanel) -> [ItemAction] {
        let actions = panel.isConfigure
            ? ItemActions.configureActions(
                hasHotkey: settings.hotkeys[panel.item.id] != nil,
                hasAlias: settings.aliases[panel.item.id] != nil
            )
            : itemActions(for: panel.item)
        let filter = panel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return actions }
        return actions.filter { SearchMatcher.match(filter, in: $0.title) != nil }
    }

    private func toggleActionPanel() {
        switch overlay {
        case .actionPanel:
            setOverlay(.none)
        case .none:
            guard let item = selectedRow?.ranked.item else { return }
            setOverlay(.actionPanel(ActionPanel(item: item, isConfigure: false)))
        case .recorder, .aliasEditor, .output, .confirmation:
            return
        }
        render()
    }

    /// ⇧⌘, — the Configure Command menu (hotkey, alias) for the selection.
    private func openConfigureCommand() {
        guard overlay.isNone, let item = selectedRow?.ranked.item, item.kind != .calculator else { return }
        setOverlay(.actionPanel(ActionPanel(item: item, isConfigure: true)))
        render()
    }

    private func runSelectedAction(_ panel: ActionPanel) {
        let actions = filteredActions(panel)
        guard let index = panel.selectedIndex, actions.indices.contains(index) else { return }
        perform(actions[index].id, on: panel.item)
    }

    /// An in-launcher shortcut: the item's action with that id, else the one sharing its
    /// shortcut (⇧⌘C copies the path, link or answer). Ignored when the item has neither.
    private func runShortcut(_ id: ItemActionID) {
        guard let item = actionTarget else { return }
        let actions = itemActions(for: item)
        let combo = ItemActions.shortcut(for: id)
        let action = actions.first { $0.id == id }
            ?? combo.flatMap { combo in actions.first { ItemActions.shortcut(for: $0.id) == combo } }
        guard let action else { return }
        perform(action.id, on: item)
    }

    /// Runs one action: `open` is the primary run (arguments, confirmation, usage);
    /// favorites, hotkeys, aliases and disabling edit settings; the rest go to the runner.
    private func perform(_ action: ItemActionID, on item: CastItem) {
        if case .actionPanel = overlay {
            setOverlay(.none)
        }
        switch action {
        case .open:
            runSelection()
        case .toggleFavorite:
            toggleFavorite(item)
        case .moveFavoriteUp:
            moveFavorite(item, by: -1)
        case .moveFavoriteDown:
            moveFavorite(item, by: 1)
        case .disableCommand:
            disable(item)
        case .setHotkey:
            openRecorder(for: item)
        case .deleteHotkey:
            applyEdits([.remove(["hotkeys", item.id.rawValue])])
        case .setAlias:
            setOverlay(.aliasEditor(AliasEditor(item: item, text: settings.aliases[item.id] ?? "", error: nil)))
        case .deleteAlias:
            applyEdits([.remove(["aliases", item.id.rawValue])])
        case .showInFinder, .copyPath, .copyBundleID, .copyLink, .copyName, .copyResult,
             .quitApplication, .hideApplication, .editScript:
            render()
            present(runner.perform(action, on: item))
            return
        }
        render()
    }

    // MARK: - Settings actions

    private func toggleFavorite(_ item: CastItem) {
        guard item.kind != .calculator else { return }
        var favorites = settings.favorites
        if let index = favorites.firstIndex(of: item.id) {
            favorites.remove(at: index)
        } else {
            favorites.append(item.id)
        }
        applyEdits([.set(favorites.map(\.rawValue), ["favorites"])])
    }

    private func moveFavorite(_ item: CastItem, by offset: Int) {
        var favorites = settings.favorites
        guard let index = favorites.firstIndex(of: item.id), favorites.indices.contains(index + offset) else { return }
        favorites.swapAt(index, index + offset)
        applyEdits([.set(favorites.map(\.rawValue), ["favorites"])])
    }

    private func disable(_ item: CastItem) {
        guard item.kind != .calculator, !settings.disabled.contains(item.id) else { return }
        let disabled = (settings.disabled.map(\.rawValue) + [item.id.rawValue]).sorted()
        if applyEdits([.set(disabled, ["disabled"])]) {
            showToast("Disabled \(item.title)", isError: false)
        }
    }

    /// Writes each edit in order (the settings center reloads and calls
    /// `settingsDidChange`); a failure shows in the footer and stops. True when all applied.
    @discardableResult
    private func applyEdits(_ edits: [SettingsEdit]) -> Bool {
        for edit in edits {
            do {
                try environment.editSettings(edit)
            } catch let error as SettingsEditError {
                showToast("settings.json line \(error.line): \(error.message)", isError: true)
                return false
            } catch {
                showToast("Couldn't edit settings.json", isError: true)
                return false
            }
        }
        return true
    }

    // MARK: - Hotkey recorder

    /// Opens the recorder on the item's current hotkey and suspends every global hotkey,
    /// so the recorder receives combos like ⌘1 itself.
    private func openRecorder(for item: CastItem) {
        let current = settings.hotkeys[item.id]
        setOverlay(.recorder(Recorder(item: item, keys: current.map { .spec($0) } ?? .display([]))))
        hotkeys.suspend()
    }

    private func recorderDidReceive(_ event: KeyEvent) {
        guard case .recorder(var session) = overlay else { return }
        let update = session.recorder.handle(event)
        switch update {
        case .pending(let display):
            // A new hold: what was recorded is being replaced.
            stopCountdown()
            session.keys = .display(display)
            session.spec = nil
            session.owner = nil
            session.countdown = nil
            overlay = .recorder(session)
        case .recorded(let spec):
            session.spec = spec
            session.keys = .spec(spec)
            session.owner = owner(of: spec, for: session.item)
            session.countdown = nil
            overlay = .recorder(session)
            if session.owner == .launcher {
                stopCountdown()
            } else {
                startCountdown()
            }
        case .cleared:
            let hasHotkey = settings.hotkeys[session.item.id] != nil
            setOverlay(.none)
            if hasHotkey {
                applyEdits([.remove(["hotkeys", session.item.id.rawValue])])
            }
        case .cancelled:
            setOverlay(.none)
        case .commit:
            overlay = .recorder(session)
            if session.spec == nil {
                setOverlay(.none)
            } else {
                saveRecordedHotkey()
            }
        case .unchanged:
            overlay = .recorder(session)
        }
        render()
    }

    /// The target already using `spec`, comparing keys by position: a character hotkey
    /// (`shift+cmd+k`) and a physical one (`shift+cmd+key:k`) on the same key conflict.
    private func owner(of spec: HotkeySpec, for item: CastItem) -> HotkeyTarget? {
        HotkeyConflicts.owner(
            of: spec,
            in: settings.hotkeyBindings,
            except: .item(item.id),
            hyperIncludesShift: settings.hyperKey.includeShift,
            keyCode: keyCode
        )
    }

    /// Saves the recorded hotkey, first removing it from the item that holds it. The
    /// launcher's own hotkey can't be taken.
    private func saveRecordedHotkey() {
        guard case .recorder(let session) = overlay, let spec = session.spec else { return }
        let owner = owner(of: spec, for: session.item)
        guard owner != .launcher else { return }
        setOverlay(.none)
        var edits: [SettingsEdit] = []
        if case .item(let other) = owner {
            edits.append(.remove(["hotkeys", other.rawValue]))
        }
        edits.append(.set(spec.settingsText, ["hotkeys", session.item.id.rawValue]))
        applyEdits(edits)
        render()
    }

    private func startCountdown() {
        stopCountdown()
        updateRecorder { $0.countdown = 0 }
        cancelCountdown = environment.schedule(Self.recorderCountdownMilliseconds) { [weak self] in
            self?.saveRecordedHotkey()
        }
        scheduleCountdownTick(elapsed: 0)
    }

    private func scheduleCountdownTick(elapsed: Int) {
        cancelCountdownTick = environment.schedule(Self.recorderTickMilliseconds) { [weak self] in
            guard let self else { return }
            let now = elapsed + Self.recorderTickMilliseconds
            guard now < Self.recorderCountdownMilliseconds else { return }
            updateRecorder { $0.countdown = Double(now) / Double(Self.recorderCountdownMilliseconds) }
            render()
            scheduleCountdownTick(elapsed: now)
        }
    }

    private func stopCountdown() {
        cancelCountdown?()
        cancelCountdown = nil
        cancelCountdownTick?()
        cancelCountdownTick = nil
    }

    private func updateRecorder(_ change: (inout Recorder) -> Void) {
        guard case .recorder(var session) = overlay else { return }
        change(&session)
        overlay = .recorder(session)
    }

    // MARK: - Alias editor

    static let aliasCharactersError = "Use only a–z, 0–9 and spaces"

    static func isValidAlias(_ text: String) -> Bool {
        text.allSatisfy { character in
            character == " " || (character.isASCII && (character.isLowercase || character.isNumber))
        }
    }

    /// ↵ in the alias editor: saves the trimmed alias, or removes it when empty.
    private func saveAlias() {
        guard case .aliasEditor(let editor) = overlay, editor.error == nil else { return }
        let alias = editor.text.trimmingCharacters(in: .whitespaces)
        let hadAlias = settings.aliases[editor.item.id] != nil
        setOverlay(.none)
        if !alias.isEmpty {
            applyEdits([.set(alias, ["aliases", editor.item.id.rawValue])])
        } else if hadAlias {
            applyEdits([.remove(["aliases", editor.item.id.rawValue])])
        }
        render()
    }

    // MARK: - Overlay

    /// Replaces the overlay. Leaving the recorder stops its countdown and resumes hotkeys.
    private func setOverlay(_ new: Overlay) {
        if case .recorder = overlay {
            if case .recorder = new {} else {
                stopCountdown()
                hotkeys.resume()
            }
        }
        overlay = new
    }

    /// Closes an overlay whose item no longer exists; refreshes the Action Panel's item.
    private func validateOverlay() {
        switch overlay {
        case .actionPanel(var panel):
            guard let item = currentItem(panel.item) else { return setOverlay(.none) }
            panel.item = item
            overlay = .actionPanel(panel)
        case .recorder(let session):
            if currentItem(session.item) == nil { setOverlay(.none) }
        case .aliasEditor(let editor):
            if currentItem(editor.item) == nil { setOverlay(.none) }
        case .confirmation(let pending):
            if currentItem(pending.item) == nil { setOverlay(.none) }
        case .none, .output:
            return
        }
    }

    /// The current version of `item` (the calculator row isn't in the catalog).
    private func currentItem(_ item: CastItem) -> CastItem? {
        item.id == .calculatorResult ? item : itemsByID[item.id]
    }

    // MARK: - Toast

    private func showToast(_ text: String, isError: Bool) {
        cancelToast?()
        toast = LauncherToast(text: text, isError: isError)
        cancelToast = environment.schedule(Self.toastMilliseconds) { [weak self] in
            guard let self else { return }
            toast = nil
            cancelToast = nil
            render()
        }
        render()
    }

    private func clearToast() {
        cancelToast?()
        cancelToast = nil
        toast = nil
    }

    // MARK: - Items and ranking

    private func sourcesDidChange() {
        rebuildItems()
        validateOverlay()
        rank(resetSelection: false)
        render()
    }

    /// Sources first, then `BuiltinItems`; the first item wins when an id repeats.
    private func rebuildItems() {
        var seen = Set<ItemID>()
        let items = sources.flatMap { $0.items } + BuiltinItems.items(settings: settings)
        allItems = items.filter { seen.insert($0.id).inserted }
        itemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    /// Re-ranks the query. `resetSelection` selects the first row; otherwise the selected
    /// item stays selected (or the row at its position when it's gone).
    private func rank(resetSelection: Bool) {
        let previous = selectedRow.map { (kind: $0.kind, id: $0.ranked.item.id) }
        let previousIndex = selectedIndex
        if let pinnedItemID, let item = itemsByID[pinnedItemID] {
            sections = [ResultSection(kind: .results, rows: [RankedItem(item: item, score: 0)])]
        } else {
            pinnedItemID = nil
            sections = Ranker.sections(
                query: query,
                items: allItems,
                settings: settings,
                usage: usage,
                now: environment.now(),
                calculator: Calculator.evaluate(query, locale: .current)
            )
        }
        let rows = flatRows
        if rows.isEmpty {
            selectedIndex = nil
        } else if !resetSelection, let previous {
            selectedIndex = rows.firstIndex { $0.kind == previous.kind && $0.ranked.item.id == previous.id }
                ?? rows.firstIndex { $0.ranked.item.id == previous.id }
                ?? min(previousIndex ?? 0, rows.count - 1)
        } else {
            selectedIndex = 0
        }
        syncArguments()
    }

    private var flatRows: [(ranked: RankedItem, kind: SectionKind)] {
        sections.flatMap { section in section.rows.map { (ranked: $0, kind: section.kind) } }
    }

    private var selectedRow: (ranked: RankedItem, kind: SectionKind)? {
        guard let selectedIndex else { return nil }
        let rows = flatRows
        return rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    /// The selection's argument fields; fallback rows take the query instead.
    private var selectionArguments: [ArgumentSpec] {
        guard let row = selectedRow, row.kind != .fallbacks else { return [] }
        return row.ranked.item.arguments
    }

    /// Argument values belong to one item: a new selection starts from its defaults.
    private func syncArguments() {
        let row = selectedRow
        let id = row.flatMap { $0.kind == .fallbacks ? nil : $0.ranked.item.id }
        guard id != argumentItemID else { return }
        argumentItemID = id
        argumentValues = Self.filled([], for: selectionArguments)
        if case .argument = focus {
            focus = .query
        }
    }

    // MARK: - Arguments

    /// `values` padded with defaults (dropdowns: their first option) to one per spec;
    /// dropdown titles become their values. Without specs the values pass through.
    static func filled(_ values: [String], for specs: [ArgumentSpec]) -> [String] {
        guard !specs.isEmpty else { return values }
        return specs.enumerated().map { index, spec in
            guard values.indices.contains(index) else { return defaultValue(for: spec) }
            return value(values[index], for: spec)
        }
    }

    /// A dropdown's option value for a title or value; text as is.
    static func value(_ text: String, for spec: ArgumentSpec) -> String {
        guard case .dropdown(let options) = spec.kind else { return text }
        if options.contains(where: { $0.value == text }) { return text }
        return options.first { $0.title == text }?.value ?? text
    }

    static func defaultValue(for spec: ArgumentSpec) -> String {
        if case .dropdown(let options) = spec.kind {
            return options.first?.value ?? ""
        }
        return ""
    }

    /// The first required argument whose value is blank.
    static func firstMissingArgument(_ specs: [ArgumentSpec], values: [String]) -> Int? {
        specs.indices.first { index in
            guard !specs[index].isOptional else { return false }
            let value = values.indices.contains(index) ? values[index] : ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Drawing

    private func presentPanel() {
        let frame = environment.screenFrame(settings.launcher.screen)
        presentedScreenFrame = frame
        presenter.present(model(), screenFrame: frame)
    }

    private func render() {
        guard isVisible else { return }
        presenter.update(model())
    }

    private func model() -> LauncherViewModel {
        let icons = icons
        return LauncherModelBuilder.model(
            theme: environment.theme(),
            query: query,
            sections: sections,
            selectedIndex: selectedIndex,
            arguments: selectionArguments,
            argumentValues: argumentValues,
            focus: focus,
            toast: toast,
            overlay: overlayModel(),
            settings: settings,
            icon: { icons.image(for: $0, size: LauncherModelBuilder.iconSize) }
        )
    }

    private func overlayModel() -> OverlayViewModel {
        switch overlay {
        case .none:
            return .none
        case .actionPanel(let panel):
            return .actionPanel(
                title: panel.isConfigure ? "Configure Command" : panel.item.title,
                query: panel.query,
                rows: LauncherModelBuilder.actionRows(filteredActions(panel)),
                selectedIndex: panel.selectedIndex
            )
        case .recorder(let session):
            return LauncherModelBuilder.recorder(
                itemTitle: session.item.title,
                keys: session.keys,
                conflict: LauncherModelBuilder.conflictText(ownerTitle: session.owner.map { title(of: $0) }),
                countdown: session.countdown
            )
        case .aliasEditor(let editor):
            return .aliasEditor(itemTitle: editor.item.title, text: editor.text, error: editor.error)
        case .output(let title, let text, let isError):
            return .output(title: title, text: text, isError: isError)
        case .confirmation(let pending):
            return .confirmation(title: pending.item.title, message: "Are you sure?", confirmTitle: pending.item.title)
        }
    }

    /// "Soprano Cast" for the launcher's hotkey, else the item's title (its id when gone).
    private func title(of target: HotkeyTarget) -> String {
        switch target {
        case .launcher: "Soprano Cast"
        case .item(let id): itemsByID[id]?.title ?? id.rawValue
        }
    }
}

// MARK: - Overlay state

private struct ActionPanel {
    var item: CastItem
    /// The Configure Command submenu instead of every action.
    var isConfigure: Bool
    var query = ""
    var selectedIndex: Int? = 0
}

private struct Recorder {
    var item: CastItem
    var recorder = HotkeyRecorder()
    /// Keycaps shown: the current hotkey, what is held, or what was recorded.
    var keys: LauncherModelBuilder.RecorderKeys
    var spec: HotkeySpec?
    var owner: HotkeyTarget?
    /// 0…1 while the auto-save counts down.
    var countdown: Double?

    init(item: CastItem, keys: LauncherModelBuilder.RecorderKeys) {
        self.item = item
        self.keys = keys
    }
}

private struct AliasEditor {
    var item: CastItem
    var text: String
    var error: String?
}

/// A run waiting for confirmation.
private struct PendingRun {
    var item: CastItem
    var arguments: [String]
    var recordsQuery: Bool
}

private enum Overlay {
    case none
    case actionPanel(ActionPanel)
    case recorder(Recorder)
    case aliasEditor(AliasEditor)
    case output(title: String, text: String, isError: Bool)
    case confirmation(PendingRun)

    var isNone: Bool {
        if case .none = self { return true }
        return false
    }

    var name: String {
        switch self {
        case .none: "none"
        case .actionPanel(let panel): panel.isConfigure ? "configureCommand" : "actionPanel"
        case .recorder: "recorder"
        case .aliasEditor: "aliasEditor"
        case .output: "output"
        case .confirmation: "confirmation"
        }
    }

    func context(focus: LauncherFocus) -> LauncherContext {
        switch self {
        case .none:
            if case .argument = focus { return .root(argumentFocused: true) }
            return .root(argumentFocused: false)
        case .actionPanel: return .actionPanel
        case .recorder: return .hotkeyRecorder
        case .aliasEditor: return .aliasEditor
        case .output: return .output
        case .confirmation: return .confirmation
        }
    }
}
