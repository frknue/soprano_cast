import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

/// The settings window on the snapshot harness's fixtures: an in-memory settings.json, the
/// launcher's items, virtual time and logged hotkey suspension.
@MainActor
private final class SettingsWindowHarness {
    let store: FixtureSettingsStore
    let support: FixturePresenterSupport
    let controller: LauncherController
    let hotkeys = FixtureHotkeys()
    let window: SettingsWindowController

    init(settings text: String = SettingsTemplate.text) throws {
        let store = try FixtureSettingsStore(text: text)
        let support = FixturePresenterSupport(settingsStore: store, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949))
        LauncherWindow.offscreen = true
        let controller = LauncherController(
            sources: [FixtureCatalog()],
            icons: FixtureIcons(),
            runner: FixtureRunner(),
            presenter: LauncherWindow(),
            hotkeys: FixtureHotkeys(),
            environment: support.environment
        )
        let window = SettingsWindowController(
            environment: support.settingsWindowEnvironment(items: { controller.allItems }),
            icons: FixtureIcons(),
            hotkeys: hotkeys,
            keyCode: LauncherController.layoutKeyCode
        )
        store.onChange = { [weak controller, weak window] in
            controller?.settingsDidChange()
            window?.settingsDidChange()
        }
        self.store = store
        self.support = support
        self.controller = controller
        self.window = window
    }

    /// Replays a snapshot `--keys` token into the recorder.
    func press(_ token: String) throws {
        var replay = SnapshotCommand.KeyReplay(hyperIncludesShift: store.settings.hyperKey.includeShift)
        for event in replay.events(for: try SnapshotCommand.keyToken(token)) {
            window.receive(event)
        }
    }
}

@MainActor
struct SettingsWindowTests {
    private let chrome = ItemID(rawValue: "app:com.google.Chrome")
    private let mail = ItemID(rawValue: "app:com.apple.mail")

    @Test("a hotkey recorded in the window saves after the countdown, taken from the item that held it, with global hotkeys suspended meanwhile")
    func recordingTakesHotkey() throws {
        let harness = try SettingsWindowHarness(settings: #"{ "hotkeys": { "app:com.apple.mail": "cmd+key:2" } }"#)
        harness.window.recordHotkey(for: .item(chrome), title: "Google Chrome")
        #expect(harness.hotkeys.log == ["suspend"])
        try harness.press("rec:cmd+2")
        #expect(harness.window.isRecording)
        #expect(harness.store.edits.isEmpty)

        try harness.support.advance(milliseconds: HotkeyRecordingSession.countdownMilliseconds)
        #expect(!harness.window.isRecording)
        #expect(harness.hotkeys.log == ["suspend", "resume"])
        #expect(harness.store.edits == ["remove hotkeys.app:com.apple.mail", "set hotkeys.app:com.google.Chrome = \"cmd+key:2\""])
        #expect(harness.store.settings.hotkeys[mail] == nil)
    }

    @Test("clearing Soprano Cast's own hotkey writes null, so ⌘Space doesn't come back")
    func clearingLauncherHotkey() throws {
        let harness = try SettingsWindowHarness()
        harness.window.recordHotkey(for: .launcher, title: "Soprano Cast")
        try harness.press("delete")
        #expect(harness.store.edits == ["set launcher.hotkey = null"])
        #expect(harness.store.settings.launcher.hotkey == nil)
        #expect(harness.hotkeys.log == ["suspend", "resume"])
    }

    @Test("escape and a click beside the card close the recorder without writing")
    func cancellingRecorder() throws {
        let harness = try SettingsWindowHarness()
        harness.window.recordHotkey(for: .item(chrome), title: "Google Chrome")
        try harness.press("rec:cmd+2")
        try harness.press("esc")
        try harness.support.advance(milliseconds: 5000)
        #expect(!harness.window.isRecording)
        #expect(harness.store.edits.isEmpty)
    }

    @Test("creating a quicklink writes an id made from its name and selects the new quicklink")
    func creatingQuicklink() throws {
        let harness = try SettingsWindowHarness()
        harness.window.show(tab: .extensions)
        harness.window.extensions.createQuicklink(QuicklinkFields(name: "GitHub Repo", link: "https://github.com/{argument}"))
        let id = ItemID(rawValue: "quicklink:github-repo")
        #expect(harness.store.settings.quicklinks == [Quicklink(id: "github-repo", name: "GitHub Repo", link: "https://github.com/{argument}")])
        #expect(harness.window.extensions.selection == .item(id))
        #expect(harness.window.extensions.listedIDs.contains(id.rawValue))

        harness.window.extensions.createQuicklink(QuicklinkFields(name: "", link: "x"))
        #expect(harness.store.edits.count == 1)
        #expect(harness.window.statusText == "A quicklink needs a name")
    }

    @Test("deleting a quicklink also drops its hotkey, alias and list entries")
    func deletingQuicklink() throws {
        let harness = try SettingsWindowHarness(settings: """
        {
          "quicklinks": [{ "id": "github", "name": "GitHub", "link": "https://github.com" }],
          "hotkeys": { "quicklink:github": "cmd+key:3" },
          "aliases": { "quicklink:github": "gh" },
          "favorites": ["quicklink:github", "app:com.apple.mail"],
          "disabled": ["quicklink:github"]
        }
        """)
        harness.window.extensions.deleteQuicklink(id: "github")
        let settings = harness.store.settings
        let github = ItemID(rawValue: "quicklink:github")
        #expect(settings.quicklinks.isEmpty)
        #expect(settings.hotkeys[github] == nil && settings.aliases[github] == nil)
        #expect(settings.favorites == [mail])
        #expect(settings.disabled.isEmpty)
        #expect(harness.window.extensions.selection == .group(.quicklinks))
    }

    @Test("an alias with other characters is refused with a status message; a valid one is saved trimmed and lowercased")
    func aliases() throws {
        let harness = try SettingsWindowHarness()
        harness.window.extensions.setAlias("G-C", for: chrome)
        #expect(harness.store.edits.isEmpty)
        #expect(harness.window.statusText == AliasText.charactersError)

        harness.window.extensions.setAlias(" GC ", for: chrome)
        #expect(harness.store.settings.aliases[chrome] == "gc")
        harness.window.extensions.setAlias("", for: chrome)
        #expect(harness.store.settings.aliases[chrome] == nil)
    }

    @Test("Enabled off hides a command from Root Search, on brings it back; favorites and fallbacks toggle")
    func enabledFavoriteFallback() throws {
        let harness = try SettingsWindowHarness()
        let extensions = harness.window.extensions
        extensions.setEnabled(false, for: mail)
        #expect(harness.store.settings.disabled == [mail])
        extensions.setEnabled(true, for: mail)
        #expect(harness.store.settings.disabled.isEmpty)

        extensions.setFavorite(true, for: chrome)
        extensions.setFallback(true, for: chrome)
        #expect(harness.store.settings.favorites == [chrome])
        #expect(harness.store.settings.fallbacks == [ItemID(kind: .castCommand, key: CastCommand.searchGoogle.rawValue), chrome])
    }

    @Test("folders are added once and removed by position")
    func folders() throws {
        let harness = try SettingsWindowHarness()
        let extensions = harness.window.extensions
        extensions.addFolder("~/Scripts", to: .scriptCommands)
        extensions.addFolder("~/Scripts", to: .scriptCommands)
        extensions.addFolder("~/Apps", to: .applications)
        #expect(harness.store.settings.scriptDirectories == ["~/Scripts"])
        #expect(harness.store.settings.applicationDirectories == ["~/Apps"])
        extensions.removeFolder(at: 0, from: .scriptCommands)
        #expect(harness.store.settings.scriptDirectories.isEmpty)
    }

    @Test("choosing no Hyper key writes null and resets a Caps Lock quick press, leaving no warnings")
    func hyperKeyTrigger() throws {
        let harness = try SettingsWindowHarness(settings: #"{ "hyperKey": { "trigger": "capsLock", "quickPress": "escape" } }"#)
        harness.window.advanced.setHyperTrigger(nil)
        #expect(harness.store.edits == ["set hyperKey.trigger = null", "set hyperKey.quickPress = \"nothing\""])
        #expect(harness.store.settings.hyperKey == HyperKeySettings())
        #expect(harness.store.issues.isEmpty)
    }
}
