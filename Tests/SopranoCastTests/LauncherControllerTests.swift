import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct LauncherControllerTests {
    private let chrome = LauncherTestItems.chrome
    private let slack = LauncherTestItems.slack
    private let greet = LauncherTestItems.greet
    private let deploy = LauncherTestItems.deploy

    private func shown(
        settings: CastSettings = CastSettings(),
        history: [String] = []
    ) -> LauncherHarness {
        let harness = LauncherHarness(settings: settings, history: history)
        harness.controller.show()
        return harness
    }

    /// ⇧⌘K as settings.json may spell it by character (`shift+cmd+k`).
    private var shiftCommandK: HotkeySpec {
        .combo(HotkeyCombo(modifiers: [.shift, .command], key: .character("k")))
    }

    /// ⇧⌘K as the recorder records it: by key position (`shift+cmd+key:k`).
    private var recordedShiftCommandK: HotkeySpec {
        .combo(HotkeyCombo(modifiers: [.shift, .command], key: .physical(0x28)))
    }

    // MARK: Search

    @Test("typing ranks the items and every query change selects the first row again")
    func typingRanksAndResetsSelection() {
        let harness = shown()
        harness.type("chrome")
        #expect(harness.snapshot.rowIDs.first == chrome.id)
        #expect(harness.snapshot.selectedID == chrome.id)

        harness.press(.down)
        #expect(harness.snapshot.selectedID != chrome.id)

        harness.type("chrom")
        #expect(harness.snapshot.selectedID == chrome.id)
        harness.type("slack")
        #expect(harness.snapshot.rowIDs.first == slack.id)
        #expect(harness.snapshot.selectedID == slack.id)
    }

    @Test("the launcher opens on the screen the settings pick with the placeholder")
    func showsOnScreen() {
        let harness = shown()
        #expect(harness.controller.isVisible)
        #expect(harness.presenter.screenFrames == [LauncherHarness.screenFrame])
        #expect(harness.model?.placeholder == "Search for apps and commands…")
    }

    // MARK: Running

    @Test("return runs the selection's primary action and closes when the outcome asks")
    func returnRunsPrimary() {
        let harness = shown()
        harness.type("chrome")
        harness.press(.return)
        #expect(harness.runner.runs == [StubRunner.Run(id: chrome.id, arguments: [])])
        #expect(!harness.controller.isVisible)
    }

    @Test("a run that doesn't ask to close leaves the launcher open")
    func doneWithoutClosing() {
        let harness = shown()
        harness.runner.outcomes[chrome.id] = .done(closeLauncher: false)
        harness.type("chrome")
        harness.press(.return)
        #expect(harness.controller.isVisible)
        #expect(harness.snapshot.query == "chrome")
    }

    @Test("running records the item's use and the query in the search history")
    func usageRecorded() {
        let harness = shown()
        harness.type("chrome")
        harness.press(.return)
        #expect(harness.savedUsage[chrome.id]?.uses == [harness.now])
        #expect(harness.savedHistory == ["chrome"])
    }

    @Test("an empty required argument gets focus first, then a toast, then the item runs with it")
    func requiredArgumentFocusesField() {
        let harness = shown()
        harness.type("greet")
        #expect(harness.snapshot.selectedID == greet.id)
        #expect(harness.model?.arguments.map { $0.placeholder } == ["Name"])

        harness.press(.return)
        #expect(harness.runner.runs.isEmpty)
        #expect(harness.model?.focus == .argument(0))

        harness.press(.return)
        #expect(harness.runner.runs.isEmpty)
        #expect(harness.snapshot.footerToast == "Fill in name")

        harness.presenter.onArgumentChange?(0, "Ada")
        harness.press(.return)
        #expect(harness.runner.runs == [StubRunner.Run(id: greet.id, arguments: ["Ada"])])
    }

    @Test("tab cycles the focus from the query through the arguments and back")
    func tabCyclesArguments() {
        let harness = shown()
        harness.type("greet")
        harness.press(.tab)
        #expect(harness.model?.focus == .argument(0))
        harness.press(.tab)
        #expect(harness.model?.focus == .query)
        harness.press(.tab, [.shift])
        #expect(harness.model?.focus == .argument(0))
    }

    @Test("argument values reset when the selection moves to another item")
    func argumentValuesFollowSelection() {
        let harness = shown()
        harness.type("greet")
        harness.presenter.onArgumentChange?(0, "Ada")
        #expect(harness.snapshot.argumentValues == ["Ada"])
        harness.press(.down)
        #expect(harness.snapshot.argumentValues.isEmpty)
        harness.press(.up)
        #expect(harness.snapshot.argumentValues == [""])
    }

    @Test("typing an alias and a space focuses the item's first argument")
    func aliasSpaceFocusesArgument() {
        var settings = CastSettings()
        settings.aliases[greet.id] = "hi"
        let harness = shown(settings: settings)
        harness.type("hi")
        harness.type("hi ")
        #expect(harness.snapshot.selectedID == greet.id)
        #expect(harness.snapshot.query == "hi")
        #expect(harness.model?.focus == .argument(0))
    }

    @Test("a command that needs confirmation asks first; Esc cancels and ↵ confirms")
    func confirmationFlow() {
        let harness = shown()
        harness.type("deploy")
        harness.press(.return)
        #expect(harness.snapshot.overlay == "confirmation")
        #expect(harness.runner.runs.isEmpty)

        harness.press(.escape)
        #expect(harness.snapshot.overlay == "none")
        #expect(harness.runner.runs.isEmpty)
        #expect(harness.controller.isVisible)

        harness.press(.return)
        harness.press(.return)
        #expect(harness.runner.runs == [StubRunner.Run(id: deploy.id, arguments: [])])
    }

    @Test("a fallback row runs its command with the query as the first argument")
    func fallbackPassesQuery() {
        let harness = shown()
        harness.type("zzqxy")
        #expect(harness.snapshot.rowIDs == [LauncherTestItems.searchGoogle])
        harness.press(.return)
        #expect(harness.runner.runs == [StubRunner.Run(id: LauncherTestItems.searchGoogle, arguments: ["zzqxy"])])
    }

    @Test("⌘↵ runs the secondary action and ⌥↵ the tertiary")
    func secondaryAndTertiary() {
        let harness = shown()
        harness.runner.actionOutcome = .done(closeLauncher: false)
        harness.type("chrome")
        harness.press(.return, [.command])
        harness.press(.return, [.option])
        #expect(harness.runner.actions == [
            StubRunner.Action(action: .showInFinder, id: chrome.id),
            StubRunner.Action(action: .copyPath, id: chrome.id),
        ])
        #expect(harness.runner.runs.isEmpty)
    }

    // MARK: Outcomes

    @Test("a HUD outcome closes the launcher and shows the HUD")
    func hudOutcome() {
        let harness = shown()
        harness.runner.outcomes[chrome.id] = .hud("Opened")
        harness.type("chrome")
        harness.press(.return)
        #expect(!harness.controller.isVisible)
        #expect(harness.presenter.huds == ["Opened"])
    }

    @Test("a toast outcome stays in the footer for three seconds")
    func toastOutcome() {
        let harness = shown()
        harness.runner.outcomes[chrome.id] = .toast("Saved", isError: false)
        harness.type("chrome")
        harness.press(.return)
        #expect(harness.controller.isVisible)
        #expect(harness.snapshot.footerToast == "Saved")
        #expect(harness.model?.footer.toast == "Saved")
        #expect(harness.scheduler.pendingDelays == [LauncherController.toastMilliseconds])
        harness.scheduler.fireAll()
        #expect(harness.snapshot.footerToast == nil)
    }

    @Test("an output outcome opens the output view, which Esc closes")
    func outputOutcome() {
        let harness = shown()
        harness.runner.outcomes[greet.id] = .output(title: "Greet", text: "Hello Ada", isError: false)
        harness.type("greet")
        harness.presenter.onArgumentChange?(0, "Ada")
        harness.press(.return)
        #expect(harness.snapshot.overlay == "output")
        guard case .output(let title, let text, _)? = harness.overlayModel else {
            Issue.record("no output overlay")
            return
        }
        #expect(title == "Greet")
        #expect(text == "Hello Ada")
        harness.press(.escape)
        #expect(harness.snapshot.overlay == "none")
        #expect(harness.controller.isVisible)
    }

    // MARK: Action Panel

    @Test("⌘K opens the Action Panel, its text filters it and ↵ runs the selected action")
    func actionPanelFilterAndRun() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: "k", [.command])
        #expect(harness.snapshot.overlay == "actionPanel")
        #expect(harness.actionTitles.first == "Open Application")
        #expect(harness.model?.focus == .overlay)

        harness.presenter.onOverlayTextChange?("copy path")
        #expect(harness.actionTitles == ["Copy Path"])
        harness.press(.return)
        #expect(harness.runner.actions == [StubRunner.Action(action: .copyPath, id: chrome.id)])
        #expect(harness.snapshot.overlay == "none")
    }

    @Test("⌘K closes the Action Panel again")
    func actionPanelToggles() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: "k", [.command])
        harness.press(character: "k", [.command])
        #expect(harness.snapshot.overlay == "none")
    }

    @Test("↵ on the Action Panel's first row runs the item like ↵ in Root Search")
    func actionPanelPrimary() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: "k", [.command])
        harness.press(.return)
        #expect(harness.runner.runs == [StubRunner.Run(id: chrome.id, arguments: [])])
        #expect(harness.runner.actions.isEmpty)
    }

    // MARK: Settings actions

    @Test("⌘F adds the selection to the favorites and removes it again")
    func favoritesEdit() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: "f", [.command])
        #expect(harness.settings.favorites == [chrome.id])
        harness.press(character: "f", [.command])
        #expect(harness.settings.favorites.isEmpty)
        #expect(harness.edits == ["set favorites = \(chrome.id.rawValue)", "set favorites = "])
    }

    @Test("⇧⌘↑ moves a favorite up")
    func moveFavoriteUp() {
        var settings = CastSettings()
        settings.favorites = [slack.id, chrome.id]
        let harness = shown(settings: settings)
        #expect(harness.snapshot.rowIDs == [slack.id, chrome.id])
        harness.press(.down)
        harness.press(.up, [.shift, .command])
        #expect(harness.settings.favorites == [chrome.id, slack.id])
        #expect(harness.snapshot.selectedID == chrome.id)
    }

    @Test("⇧⌘D disables the selection with a toast and drops it from the results")
    func disableCommand() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: "d", [.shift, .command])
        #expect(harness.settings.disabled == [chrome.id])
        #expect(harness.snapshot.footerToast == "Disabled Google Chrome")
        #expect(!harness.snapshot.rowIDs.contains(chrome.id))
    }

    // MARK: Hotkey recorder

    /// Opens Configure Command on Chrome and picks Set Hotkey.
    private func openRecorder(_ harness: LauncherHarness) {
        harness.type("chrome")
        harness.press(character: ",", [.shift, .command])
        #expect(harness.snapshot.overlay == "configureCommand")
        #expect(harness.actionTitles.first == "Set Hotkey…")
        harness.press(.return)
        #expect(harness.snapshot.overlay == "recorder")
    }

    @Test("Set Hotkey records ⇧⌘K and the countdown saves it, suspending hotkeys meanwhile")
    func recorderSavesAfterCountdown() {
        let harness = shown()
        openRecorder(harness)
        #expect(harness.hotkeys.suspendCount == 1)

        harness.recordShiftCommandK()
        guard case .recorder(_, let keys, let conflict, let countdown, _)? = harness.overlayModel else {
            Issue.record("no recorder overlay")
            return
        }
        #expect(keys == KeyboardLayout.keycaps(for: recordedShiftCommandK))
        #expect(conflict == nil)
        #expect(countdown == 0)
        #expect(harness.edits.isEmpty)

        harness.scheduler.fire(milliseconds: HotkeyRecordingSession.tickMilliseconds)
        guard case .recorder(_, _, _, let progress?, _)? = harness.overlayModel else {
            Issue.record("no countdown")
            return
        }
        #expect(progress > 0)

        harness.scheduler.fireAll()
        #expect(harness.edits == ["set hotkeys.\(chrome.id.rawValue) = \(recordedShiftCommandK.settingsText)"])
        #expect(harness.settings.hotkeys[chrome.id] == recordedShiftCommandK)
        #expect(harness.snapshot.overlay == "none")
        #expect(harness.hotkeys.resumeCount == 1)
    }

    @Test("a character hotkey another command uses on the same key shows its owner and saving moves it over")
    func recorderOverwritesOwner() {
        var settings = CastSettings()
        settings.hotkeys[slack.id] = shiftCommandK
        let harness = shown(settings: settings)
        openRecorder(harness)
        harness.recordShiftCommandK()
        guard case .recorder(_, _, let conflict, _, _)? = harness.overlayModel else {
            Issue.record("no recorder overlay")
            return
        }
        #expect(conflict == "Used by Slack")

        harness.press(.return)
        #expect(harness.edits == [
            "remove hotkeys.\(slack.id.rawValue)",
            "set hotkeys.\(chrome.id.rawValue) = \(recordedShiftCommandK.settingsText)",
        ])
        #expect(harness.settings.hotkeys == [chrome.id: recordedShiftCommandK])
    }

    @Test("the launcher's own hotkey shows as used by Soprano Cast and can't be saved")
    func recorderRejectsLauncherHotkey() {
        let harness = shown()
        openRecorder(harness)
        harness.recordCommandSpace()
        guard case .recorder(_, _, let conflict, let countdown, _)? = harness.overlayModel else {
            Issue.record("no recorder overlay")
            return
        }
        #expect(conflict == "Used by Soprano Cast")
        #expect(countdown == nil)
        #expect(harness.scheduler.pendingDelays.isEmpty)

        harness.press(.return)
        #expect(harness.snapshot.overlay == "recorder")
        #expect(harness.edits.isEmpty)

        harness.press(.escape)
        #expect(harness.snapshot.overlay == "none")
        #expect(harness.edits.isEmpty)
        #expect(harness.hotkeys.suspendCount == 1)
        #expect(harness.hotkeys.resumeCount == 1)
    }

    @Test("⌫ in the recorder removes the item's hotkey")
    func recorderClears() {
        var settings = CastSettings()
        settings.hotkeys[chrome.id] = shiftCommandK
        let harness = shown(settings: settings)
        openRecorder(harness)
        harness.press(.delete)
        #expect(harness.edits == ["remove hotkeys.\(chrome.id.rawValue)"])
        #expect(harness.settings.hotkeys.isEmpty)
        #expect(harness.hotkeys.resumeCount == 1)
    }

    @Test("hiding the launcher while recording resumes the hotkeys")
    func hidingLeavesRecorder() {
        let harness = shown()
        openRecorder(harness)
        harness.controller.hide()
        #expect(harness.hotkeys.resumeCount == 1)
        harness.controller.show()
        #expect(harness.snapshot.overlay == "none")
    }

    // MARK: Alias editor

    @Test("the alias editor rejects other characters and saves a valid alias")
    func aliasEditor() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: ",", [.shift, .command])
        harness.presenter.onOverlayTextChange?("alias")
        #expect(harness.actionTitles == ["Set Alias…"])
        harness.press(.return)
        #expect(harness.snapshot.overlay == "aliasEditor")

        harness.presenter.onOverlayTextChange?("GC!")
        guard case .aliasEditor(_, let text, let error)? = harness.overlayModel else {
            Issue.record("no alias editor")
            return
        }
        #expect(text == "gc!")
        #expect(error != nil)
        harness.press(.return)
        #expect(harness.snapshot.overlay == "aliasEditor")
        #expect(harness.edits.isEmpty)

        harness.presenter.onOverlayTextChange?("GC")
        harness.press(.return)
        #expect(harness.edits == ["set aliases.\(chrome.id.rawValue) = gc"])
        #expect(harness.settings.aliases[chrome.id] == "gc")
        #expect(harness.snapshot.overlay == "none")
    }

    // MARK: Back, pop to root, close

    @Test("Esc closes the overlay first, then the window")
    func escapeClosesOverlayThenWindow() {
        let harness = shown()
        harness.type("chrome")
        harness.press(character: "k", [.command])
        harness.press(.escape)
        #expect(harness.snapshot.overlay == "none")
        #expect(harness.controller.isVisible)
        harness.press(.escape)
        #expect(!harness.controller.isVisible)
    }

    @Test("⌘Esc pops to root and keeps the window open")
    func commandEscapePopsToRoot() {
        let harness = shown()
        harness.type("greet")
        harness.presenter.onArgumentChange?(0, "Ada")
        harness.press(character: "k", [.command])
        harness.press(.escape, [.command])
        #expect(harness.snapshot.query == "")
        #expect(harness.snapshot.overlay == "none")
        #expect(harness.snapshot.argumentValues.isEmpty)
        #expect(harness.controller.isVisible)
    }

    @Test("⌘W closes the window")
    func commandWCloses() {
        let harness = shown()
        harness.press(character: "w", [.command])
        #expect(!harness.controller.isVisible)
    }

    @Test("reopening within popToRootSeconds keeps the search; later it starts over")
    func popToRootTimeout() {
        let harness = shown()
        harness.type("chrome")
        harness.press(.escape)

        harness.now = harness.now.addingTimeInterval(60)
        harness.controller.show()
        #expect(harness.snapshot.query == "chrome")
        #expect(harness.snapshot.selectedID == chrome.id)

        harness.press(.escape)
        harness.now = harness.now.addingTimeInterval(91)
        harness.controller.show()
        #expect(harness.snapshot.query == "")
    }

    @Test("losing focus closes the launcher only with closeOnFocusLoss")
    func focusLoss() {
        let harness = shown()
        harness.presenter.onResignKey?()
        #expect(!harness.controller.isVisible)

        var settings = CastSettings()
        settings.launcher.closeOnFocusLoss = false
        let keeping = shown(settings: settings)
        keeping.presenter.onResignKey?()
        #expect(keeping.controller.isVisible)
    }

    // MARK: History

    @Test("↑ at the top steps back through past queries and ↓ at the bottom returns to typing")
    func historyAtTop() {
        // Queries nothing matches: the only row is the fallback, both top and bottom.
        let harness = shown(history: ["qqzz one", "qqzz two"])
        harness.press(.up)
        #expect(harness.snapshot.query == "qqzz one")
        harness.press(.up)
        #expect(harness.snapshot.query == "qqzz two")
        harness.press(.down)
        #expect(harness.snapshot.query == "qqzz one")
        harness.press(.down)
        #expect(harness.snapshot.query == "")
    }

    @Test("typing after browsing the history starts from the newest entry again")
    func typingResetsHistoryCursor() {
        let harness = shown(history: ["qqzz one", "qqzz two"])
        harness.press(.up)
        harness.press(.up)
        harness.type("x")
        harness.type("")
        harness.press(.up)
        #expect(harness.snapshot.query == "qqzz one")
    }

    // MARK: run(itemID:)

    @Test("run(itemID:) runs the item without showing the launcher")
    func runWithoutShowing() {
        let harness = LauncherHarness()
        harness.controller.run(itemID: chrome.id, arguments: [])
        #expect(harness.runner.runs == [StubRunner.Run(id: chrome.id, arguments: [])])
        #expect(harness.presenter.presentCount == 0)
        #expect(!harness.controller.isVisible)
    }

    @Test("run(itemID:) shows a HUD outcome while the launcher stays hidden")
    func runShowsHUD() {
        let harness = LauncherHarness()
        harness.runner.outcomes[chrome.id] = .toast("Done", isError: false)
        harness.controller.run(itemID: chrome.id, arguments: [])
        #expect(harness.presenter.huds == ["Done"])
        #expect(!harness.controller.isVisible)
    }

    @Test("run(itemID:) on an item missing a required argument opens the launcher on it")
    func runWithMissingArguments() {
        let harness = LauncherHarness()
        harness.controller.run(itemID: greet.id, arguments: [])
        #expect(harness.runner.runs.isEmpty)
        #expect(harness.controller.isVisible)
        #expect(harness.snapshot.rowIDs == [greet.id])
        #expect(harness.model?.focus == .argument(0))

        harness.presenter.onArgumentChange?(0, "Ada")
        harness.press(.return)
        #expect(harness.runner.runs == [StubRunner.Run(id: greet.id, arguments: ["Ada"])])
    }

    @Test("run(itemID:) with its arguments runs at once")
    func runWithArguments() {
        let harness = LauncherHarness()
        harness.controller.run(itemID: greet.id, arguments: ["Ada"])
        #expect(harness.runner.runs == [StubRunner.Run(id: greet.id, arguments: ["Ada"])])
        #expect(!harness.controller.isVisible)
    }

    @Test("an app's hotkey hides the app when it is already in front and closes the launcher")
    func hotkeyHidesFrontmostApp() {
        let harness = LauncherHarness()
        harness.runner.frontmostIDs = [chrome.id]
        harness.runner.actionOutcome = .done(closeLauncher: true)
        harness.controller.show()
        harness.controller.runHotkey(itemID: chrome.id)
        #expect(harness.runner.actions == [StubRunner.Action(action: .hideApplication, id: chrome.id)])
        #expect(harness.runner.runs.isEmpty)
        #expect(!harness.controller.isVisible)
    }

    @Test("an app's hotkey opens the app when another app is in front")
    func hotkeyOpensBackgroundApp() {
        let harness = LauncherHarness()
        harness.runner.frontmostIDs = [slack.id]
        harness.controller.runHotkey(itemID: chrome.id)
        #expect(harness.runner.runs == [StubRunner.Run(id: chrome.id, arguments: [])])
        #expect(harness.runner.actions.isEmpty)
    }

    @Test("allItems lists the sources' items and the built-in commands")
    func allItems() {
        let harness = LauncherHarness()
        let ids = Set(harness.controller.allItems.map { $0.id })
        #expect(ids.contains(chrome.id))
        #expect(ids.contains(LauncherTestItems.searchGoogle))
    }

    @Test("a source change re-ranks the open launcher")
    func sourceChange() {
        let harness = shown()
        harness.type("arc")
        #expect(!harness.snapshot.rowIDs.contains(ItemID(rawValue: "app:company.thebrowser.Browser")))
        harness.source.items.append(CastItem(
            id: ItemID(rawValue: "app:company.thebrowser.Browser"), title: "Arc", icon: .file(path: "/Applications/Arc.app")
        ))
        harness.source.onChange?()
        #expect(harness.snapshot.rowIDs.first == ItemID(rawValue: "app:company.thebrowser.Browser"))
    }
}
