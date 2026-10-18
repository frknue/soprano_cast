import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct FixtureCatalogTests {
    @Test("every fixture item has a unique id")
    func uniqueIDs() {
        let ids = FixtureCatalog().items.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("apps are application items keyed by their real bundle ids, listed with their folder")
    func apps() {
        let apps = FixtureCatalog().items.filter { $0.kind == .application }
        #expect(apps.count == 14)
        #expect(apps.contains { $0.id.rawValue == "app:com.google.Chrome" && $0.title == "Google Chrome" })
        #expect(apps.contains { $0.id.rawValue == "app:net.whatsapp.WhatsApp" })
        for app in apps {
            #expect(app.subtitle.hasPrefix("/"))
            #expect(app.icon == .file(path: "\(app.subtitle)/\(app.title).app"))
        }
    }

    @Test("the three scripts cover an argument and full output and run in their mode")
    func scripts() {
        let catalog = FixtureCatalog()
        let scripts = catalog.items.filter { $0.kind == .script }
        #expect(scripts.count == 3)
        #expect(scripts.allSatisfy { $0.id.key.hasPrefix("/fixtures/") })
        #expect(scripts.filter { !$0.arguments.isEmpty }.count == 1)
        #expect(catalog.items.count == FixtureCatalog.apps.count + FixtureCatalog.scripts.count)

        let runner = FixtureRunner()
        var outcomes: [String: RunOutcome] = [:]
        for script in scripts {
            runner.run(script, arguments: script.arguments.map { _ in "bug" }) { outcomes[script.title] = $0 }
        }
        #expect(outcomes["Keep Awake"] == .hud("Staying awake for 60 minutes"))
        #expect(outcomes["Search Issues"] == .toast("Opened 3 matching issues", isError: false))
        let diskUsage = FixtureCatalog.scripts[2]
        #expect(outcomes["Disk Usage"] == .output(title: "Disk Usage", text: diskUsage.output, isError: false))
        #expect(runner.log.contains("run script:/fixtures/scripts/search-issues.sh \"bug\""))
    }

    @Test("the runner closes the launcher for apps and records actions")
    func runner() {
        let runner = FixtureRunner()
        let chrome = FixtureCatalog().items[0]
        var outcome: RunOutcome?
        runner.run(chrome, arguments: []) { outcome = $0 }
        #expect(outcome == .done(closeLauncher: true))
        #expect(runner.perform(.copyPath, on: chrome) == .done(closeLauncher: true))
        #expect(runner.log == ["run app:com.google.Chrome", "perform copyPath app:com.google.Chrome"])
        #expect(runner.isRunning(chrome))
    }

    @Test("icons are drawn at the requested size and cached")
    func icons() {
        let icons = FixtureIcons()
        let tile = icons.image(for: .file(path: "/Applications/Safari.app"), size: 24)
        #expect(tile.size == NSSize(width: 24, height: 24))
        #expect(icons.image(for: .file(path: "/Applications/Safari.app"), size: 24) === tile)
        #expect(icons.image(for: .glyph(.gear), size: 32).size == NSSize(width: 32, height: 32))
        #expect(icons.image(for: .emoji("💾"), size: 24) !== tile)
    }

    @Test("settings edits apply to the in-memory document and are recorded")
    func settingsStore() throws {
        let store = try FixtureSettingsStore()
        var changes = 0
        store.onChange = { changes += 1 }
        try store.apply(.set("cmd+2", ["hotkeys", "app:com.google.Chrome"]))
        #expect(store.settings.hotkeys[ItemID(rawValue: "app:com.google.Chrome")] != nil)
        try store.apply(.remove(["hotkeys", "app:com.google.Chrome"]))
        #expect(store.settings.hotkeys.isEmpty)
        #expect(store.edits == ["set hotkeys.app:com.google.Chrome = \"cmd+2\"", "remove hotkeys.app:com.google.Chrome"])
        #expect(changes == 2)
    }

    @Test("scheduled work runs only when virtual time passes, in due order")
    func scheduler() throws {
        let support = FixturePresenterSupport(settingsStore: try FixtureSettingsStore(), visibleFrame: .zero)
        var ran: [String] = []
        _ = support.schedule(after: 300) { ran.append("late") }
        _ = support.schedule(after: 100) {
            ran.append("early")
            _ = support.schedule(after: 100) { ran.append("chained") }
        }
        let cancel = support.schedule(after: 50) { ran.append("cancelled") }
        cancel()
        #expect(ran.isEmpty)
        try support.advance(milliseconds: 250)
        #expect(ran == ["early", "chained"])
        #expect(support.now == FixturePresenterSupport.referenceDate.addingTimeInterval(0.25))
        try support.advance(milliseconds: 100)
        #expect(ran == ["early", "chained", "late"])
        #expect(support.pendingWorkCount == 0)
    }
}
