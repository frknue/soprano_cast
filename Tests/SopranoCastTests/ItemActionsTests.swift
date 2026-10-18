import AppKit
import Testing
@testable import SopranoCastCore

struct ItemActionsTests {
    private let app = CastItem(id: ItemID(rawValue: "app:com.google.Chrome"), title: "Google Chrome",
                               icon: .file(path: "/Applications/Google Chrome.app"))
    private let pathApp = CastItem(id: ItemID(rawValue: "app:/Users/me/Tools/Thing.app"), title: "Thing",
                                   icon: .file(path: "/Users/me/Tools/Thing.app"))
    private let quicklink = CastItem(id: ItemID(rawValue: "quicklink:gh"), title: "GitHub", icon: .glyph(.link))
    private let script = CastItem(id: ItemID(rawValue: "script:/Users/me/scripts/hello.sh"), title: "Hello",
                                  icon: .glyph(.script))
    private let system = CastItem(id: ItemID(rawValue: "system:lockScreen"), title: "Lock Screen", icon: .glyph(.lock))
    private let window = CastItem(id: ItemID(rawValue: "window:leftHalf"), title: "Left Half", icon: .glyph(.window))
    private let calculator = CastItem(id: .calculatorResult, title: "4", icon: .glyph(.calculator))

    private func ids(_ item: CastItem, running: Bool = false, favorite: Bool = false, up: Bool = false,
                     down: Bool = false, hotkey: Bool = false, alias: Bool = false) -> [ItemActionID] {
        actions(item, running: running, favorite: favorite, up: up, down: down, hotkey: hotkey, alias: alias).map { $0.id }
    }

    private func actions(_ item: CastItem, running: Bool = false, favorite: Bool = false, up: Bool = false,
                         down: Bool = false, hotkey: Bool = false, alias: Bool = false) -> [ItemAction] {
        ItemActions.actions(for: item, isRunning: running, isFavorite: favorite, canMoveFavoriteUp: up,
                            canMoveFavoriteDown: down, hasHotkey: hotkey, hasAlias: alias)
    }

    @Test("an application lists open, Finder, copy and configure actions in Raycast's order")
    func applicationActions() {
        #expect(ids(app) == [
            .open, .showInFinder, .copyPath, .copyBundleID, .toggleFavorite, .setHotkey, .setAlias, .disableCommand,
        ])
        #expect(actions(app).map { $0.title } == [
            "Open Application", "Show in Finder", "Copy Path", "Copy Bundle Identifier", "Add to Favorites",
            "Set Hotkey…", "Set Alias…", "Disable Command",
        ])
    }

    @Test("a running application adds quit and hide after the copy actions")
    func runningApplication() {
        #expect(ids(app, running: true) == [
            .open, .showInFinder, .copyPath, .copyBundleID, .quitApplication, .hideApplication,
            .toggleFavorite, .setHotkey, .setAlias, .disableCommand,
        ])
        let titles = actions(app, running: true).map { $0.title }
        #expect(titles.contains("Quit Application"))
        #expect(titles.contains("Hide Application"))
        #expect(!ids(quicklink, running: true).contains(.quitApplication))
    }

    @Test("an application without a bundle identifier copies its name instead")
    func pathApplication() {
        #expect(ids(pathApp).contains(.copyName))
        #expect(!ids(pathApp).contains(.copyBundleID))
    }

    @Test("quicklinks, scripts and commands get their kind's actions without repeating primary or secondary")
    func otherKinds() {
        #expect(ids(quicklink) == [.open, .copyLink, .copyName, .toggleFavorite, .setHotkey, .setAlias, .disableCommand])
        #expect(ids(script) == [
            .open, .editScript, .showInFinder, .copyPath, .copyName, .toggleFavorite, .setHotkey, .setAlias, .disableCommand,
        ])
        #expect(ids(system) == [.open, .copyName, .toggleFavorite, .setHotkey, .setAlias, .disableCommand])
        #expect(ids(window) == ids(system))
    }

    @Test("the calculator row only offers its primary Copy Answer")
    func calculatorActions() {
        let list = actions(calculator, favorite: true, hotkey: true, alias: true)
        #expect(list.map { $0.id } == [.open])
        #expect(list.map { $0.title } == ["Copy Answer"])
        #expect(ItemActions.secondary(for: calculator) == nil)
        #expect(ItemActions.tertiary(for: calculator) == nil)
    }

    @Test("favorites flip the favorite title and offer moves only where possible")
    func favorites() {
        let favorite = actions(app, favorite: true, up: true, down: false)
        let toggle = favorite.first { $0.id == .toggleFavorite }
        #expect(toggle?.title == "Remove from Favorites")
        #expect(toggle?.isDestructive == true)
        #expect(favorite.contains { $0.id == .moveFavoriteUp && $0.title == "Move Up in Favorites" })
        #expect(!favorite.contains { $0.id == .moveFavoriteDown })

        let last = ids(app, favorite: true, up: true, down: true)
        let index = last.firstIndex(of: .toggleFavorite)!
        #expect(Array(last[index...].prefix(3)) == [.toggleFavorite, .moveFavoriteUp, .moveFavoriteDown])
        #expect(actions(app, favorite: true, down: true).contains { $0.title == "Move Down in Favorites" })

        let notFavorite = ids(app, favorite: false, up: true, down: true)
        #expect(!notFavorite.contains(.moveFavoriteUp))
        #expect(!notFavorite.contains(.moveFavoriteDown))
        #expect(actions(app).first { $0.id == .toggleFavorite }?.isDestructive == false)
    }

    @Test("removal entries appear right after their set action when a hotkey or alias exists")
    func removals() {
        let all = ids(app, hotkey: true, alias: true)
        #expect(Array(all.suffix(5)) == [.setHotkey, .deleteHotkey, .setAlias, .deleteAlias, .disableCommand])
        let titles = actions(app, hotkey: true, alias: true).map { $0.title }
        #expect(titles.contains("Remove Hotkey"))
        #expect(titles.contains("Remove Alias"))
        #expect(Array(ids(app, alias: true).suffix(4)) == [.setHotkey, .setAlias, .deleteAlias, .disableCommand])
    }

    @Test("quit, remove and disable actions are destructive; the rest aren't")
    func destructive() {
        let all = actions(app, running: true, favorite: true, up: true, down: true, hotkey: true, alias: true)
        let destructive = Set(all.filter { $0.isDestructive }.map { $0.id })
        #expect(destructive == [.quitApplication, .toggleFavorite, .deleteHotkey, .deleteAlias, .disableCommand])
    }

    @Test("the configure submenu holds hotkey and alias actions")
    func configure() {
        #expect(ItemActions.configureActions(hasHotkey: false, hasAlias: false).map { $0.id } == [.setHotkey, .setAlias])
        #expect(ItemActions.configureActions(hasHotkey: true, hasAlias: true).map { $0.id }
            == [.setHotkey, .deleteHotkey, .setAlias, .deleteAlias])
    }

    @Test("primary actions open with a per-kind title and show return")
    func primary() {
        #expect(ItemActions.primary(for: app).title == "Open Application")
        #expect(ItemActions.primary(for: quicklink).title == "Open Quicklink")
        #expect(ItemActions.primary(for: script).title == "Run Script")
        #expect(ItemActions.primary(for: system).title == "Run Command")
        #expect(ItemActions.primary(for: window).title == "Run Command")
        #expect(ItemActions.primary(for: calculator).title == "Copy Answer")
        for item in [app, quicklink, script, system, window, calculator] {
            #expect(ItemActions.primary(for: item).id == .open)
            #expect(ItemActions.primary(for: item).shortcut == HotkeyCombo(modifiers: [], key: .named(.return)))
        }
    }

    @Test("secondary and tertiary actions exist only for the kinds that have them")
    func secondaryAndTertiary() {
        #expect(ItemActions.secondary(for: app)?.id == .showInFinder)
        #expect(ItemActions.secondary(for: quicklink)?.id == .copyLink)
        #expect(ItemActions.secondary(for: script)?.id == .editScript)
        #expect(ItemActions.secondary(for: calculator) == nil)
        #expect(ItemActions.secondary(for: system) == nil)
        #expect(ItemActions.secondary(for: app)?.shortcut == HotkeyCombo(modifiers: .command, key: .named(.return)))
        #expect(ItemActions.tertiary(for: app)?.id == .copyPath)
        #expect(ItemActions.tertiary(for: app)?.shortcut == HotkeyCombo(modifiers: .option, key: .named(.return)))
        #expect(ItemActions.tertiary(for: script) == nil)
        #expect(ItemActions.tertiary(for: quicklink) == nil)
    }

    @Test("in-launcher shortcuts follow the table and other actions have none")
    func shortcuts() {
        func character(_ modifiers: ModifierSet, _ key: Character) -> HotkeyCombo {
            HotkeyCombo(modifiers: modifiers, key: .character(key))
        }
        let expected: [ItemActionID: HotkeyCombo] = [
            .open: character(.command, "o"),
            .showInFinder: character([.shift, .command], "o"),
            .copyPath: character([.shift, .command], "c"),
            .copyLink: character([.shift, .command], "c"),
            .copyBundleID: character([.option, .command], "c"),
            .copyName: character([.option, .command], "c"),
            .editScript: character(.command, "e"),
            .toggleFavorite: character(.command, "f"),
            .moveFavoriteUp: HotkeyCombo(modifiers: [.shift, .command], key: .named(.up)),
            .moveFavoriteDown: HotkeyCombo(modifiers: [.shift, .command], key: .named(.down)),
            .disableCommand: character([.shift, .command], "d"),
        ]
        for action in ItemActionID.allCases {
            #expect(ItemActions.shortcut(for: action) == expected[action], "\(action)")
        }
        #expect(actions(app).first { $0.id == .copyPath }?.shortcut == character([.shift, .command], "c"))
    }
}
