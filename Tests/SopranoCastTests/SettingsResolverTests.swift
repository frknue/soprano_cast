import AppKit
import Testing
@testable import SopranoCastCore

struct SettingsResolverTests {
    private let chrome = ItemID(rawValue: "app:com.google.Chrome")
    private let safari = ItemID(rawValue: "app:com.apple.Safari")
    private let leftHalf = ItemID(rawValue: "window:leftHalf")

    private func resolve(_ text: String, themes: Set<String> = ["nord"]) -> SettingsResolution {
        SettingsResolver.resolve(text: text, knownThemeIDs: themes)
    }

    private func settings(_ text: String) -> CastSettings {
        resolve(text).settings ?? CastSettings()
    }

    private func warnings(_ resolution: SettingsResolution) -> [String] {
        resolution.issues.filter { $0.severity == .warning }.map { $0.message }
    }

    private func warns(_ resolution: SettingsResolution, _ fragment: String) -> Bool {
        warnings(resolution).contains { $0.contains(fragment) }
    }

    private func combo(_ modifiers: ModifierSet, _ key: KeySpec, hyper: Bool = false) -> HotkeySpec {
        .combo(HotkeyCombo(modifiers: modifiers, usesHyper: hyper, key: key))
    }

    @Test("an empty object resolves to the defaults without issues")
    func emptyObject() {
        let resolution = resolve("{}")
        #expect(resolution.settings == .defaults)
        #expect(resolution.issues.isEmpty)
    }

    @Test("comments, trailing commas and every section apply over the defaults")
    func fullDocument() {
        let resolution = resolve("""
        // header
        {
          "theme": "nord",
          "launcher": { "hotkey": "opt+space", "screen": "primary", "popToRootSeconds": 0, "navigation": "both", "closeOnFocusLoss": false },
          "hotkeys": { "app:com.google.Chrome": "cmd+1", "window:leftHalf": "ctrl+opt+left" },
          "aliases": { "app:com.google.Chrome": "GC" },
          "favorites": ["app:com.google.Chrome", "window:leftHalf"],
          "disabled": ["system:toggleHiddenFiles"],
          "fallbacks": [],
          "quicklinks": [{ "id": "github", "name": "GitHub", "link": "https://github.com/{argument}", "openWith": "com.google.Chrome", "icon": "🐙" }],
          "scriptDirectories": ["~/raycast-scripts"],
          "applicationDirectories": ["~/Apps"],
          "hyperKey": { "trigger": "capsLock", "includeShift": false, "quickPress": "escape" },
          "windowManagement": { "gap": 8, "halves": "cycleSizes" },
          "app": { "startAtLogin": false, "showMenuBarIcon": false }, /* trailing */
        }
        """)
        #expect(resolution.issues.isEmpty)
        let settings = resolution.settings ?? CastSettings()
        #expect(settings.theme == "nord")
        #expect(settings.launcher.hotkey == combo(.option, .named(.space)))
        #expect(settings.launcher.screen == .primary)
        #expect(settings.launcher.popToRootSeconds == 0)
        #expect(settings.launcher.navigation == .both)
        #expect(!settings.launcher.closeOnFocusLoss)
        #expect(settings.hotkeys == [chrome: combo(.command, .character("1")), leftHalf: combo([.control, .option], .named(.left))])
        #expect(settings.aliases == [chrome: "gc"])
        #expect(settings.favorites == [chrome, leftHalf])
        #expect(settings.disabled == [ItemID(kind: .systemCommand, key: "toggleHiddenFiles")])
        #expect(settings.fallbacks.isEmpty)
        #expect(settings.quicklinks == [Quicklink(id: "github", name: "GitHub", link: "https://github.com/{argument}", openWith: "com.google.Chrome", icon: "🐙")])
        #expect(settings.scriptDirectories == ["~/raycast-scripts"])
        #expect(settings.applicationDirectories == ["~/Apps"])
        #expect(settings.hyperKey == HyperKeySettings(trigger: .capsLock, includeShift: false, quickPress: .escape))
        #expect(settings.windowManagement == WindowManagementSettings(gap: 8, halves: .cycleSizes))
        #expect(settings.app == AppBehaviorSettings(startAtLogin: false, showMenuBarIcon: false))
    }

    @Test("a parse error gives no settings and one error with its line")
    func parseError() {
        let resolution = resolve("{\n  \"theme\": \"nord\",\n  \"launcher\": nope\n}")
        #expect(resolution.settings == nil)
        #expect(resolution.issues.count == 1)
        #expect(resolution.issues.first?.severity == .error)
        #expect(resolution.issues.first?.line == 3)
    }

    @Test("a document that is not an object is an error on its first line")
    func nonObjectDocument() {
        let resolution = resolve("// comment\n\n[1, 2]")
        #expect(resolution.settings == nil)
        #expect(resolution.issues == [ConfigIssue(severity: .error, message: "settings.json must be a JSON object", line: 3)])
    }

    @Test("unknown keys warn with their dotted paths and the rest applies")
    func unknownKeys() {
        let resolution = resolve("""
        {
          "colour": 1,
          "launcher": { "hotKey": "cmd+k", "screen": "primary" },
          "hyperKey": { "key": "capsLock" },
          "quicklinks": [{ "id": "a", "name": "A", "link": "https://a.com", "url": "x" }]
        }
        """)
        #expect(warnings(resolution) == [
            "Unknown setting \"colour\".",
            "Unknown setting \"launcher.hotKey\".",
            "Unknown setting \"hyperKey.key\".",
            "Unknown setting \"quicklinks[0].url\".",
        ])
        #expect(resolution.settings?.launcher.screen == .primary)
        #expect(resolution.settings?.quicklinks.count == 1)
    }

    @Test("an unknown theme keeps the default and names the known themes")
    func unknownTheme() {
        let resolution = resolve(#"{ "theme": "dracula" }"#)
        #expect(resolution.settings?.theme == "soprano")
        #expect(warns(resolution, "theme: \"dracula\" is not a known theme; kept \"soprano\". Known themes: \"soprano\", \"nord\"."))
    }

    @Test("a section that is not an object is ignored with a warning")
    func sectionNotObject() {
        let resolution = resolve(#"{ "launcher": 3, "hotkeys": [] }"#)
        #expect(resolution.settings?.launcher == LauncherSettings())
        #expect(warns(resolution, "launcher: 3 is not an object; ignored."))
        #expect(warns(resolution, "hotkeys: an array is not an object; ignored."))
    }

    // MARK: Item ids

    @Test("item ids with an unknown kind prefix are dropped everywhere; missing items are kept")
    func unknownItemPrefix() {
        let resolution = resolve("""
        {
          "hotkeys": { "application:com.google.Chrome": "cmd+1", "app:com.not.installed": "cmd+2" },
          "aliases": { "chrome": "gc" },
          "favorites": ["foo:bar", "app:com.google.Chrome", "app:"],
          "disabled": ["nope"],
          "fallbacks": ["cast:searchGoogle", "web:google"]
        }
        """)
        let settings = resolution.settings ?? CastSettings()
        #expect(settings.hotkeys == [ItemID(rawValue: "app:com.not.installed"): combo(.command, .character("2"))])
        #expect(settings.aliases.isEmpty)
        #expect(settings.favorites == [chrome])
        #expect(settings.disabled.isEmpty)
        #expect(settings.fallbacks == [ItemID(kind: .castCommand, key: "searchGoogle")])
        #expect(warns(resolution, "hotkeys.application:com.google.Chrome: \"application:com.google.Chrome\" is not an item id"))
        #expect(warns(resolution, "aliases.chrome: \"chrome\" is not an item id"))
        #expect(warns(resolution, "favorites[0]: \"foo:bar\" is not an item id"))
        #expect(warns(resolution, "favorites[2]: \"app:\" is not an item id"))
        #expect(warns(resolution, "disabled[0]: \"nope\" is not an item id"))
        #expect(warns(resolution, "fallbacks[1]: \"web:google\" is not an item id"))
        #expect(warnings(resolution).count == 6)
    }

    @Test("item lists drop repeats and non-strings and keep the default when not an array")
    func itemLists() {
        let resolution = resolve(#"{ "favorites": ["app:a", 3, "app:a"], "fallbacks": "cast:searchGoogle" }"#)
        #expect(resolution.settings?.favorites == [ItemID(rawValue: "app:a")])
        #expect(resolution.settings?.fallbacks == CastSettings.defaults.fallbacks)
        #expect(warns(resolution, "favorites[1]: 3 is not an item id; dropped."))
        #expect(warns(resolution, "favorites[2]: \"app:a\" is listed twice; dropped."))
        #expect(warns(resolution, "fallbacks: \"cast:searchGoogle\" is not an array of item ids; kept \"cast:searchGoogle\"."))
    }

    // MARK: Hotkeys

    @Test("every hotkey shape parses; null removes a hotkey without a warning")
    func hotkeyShapes() {
        let resolution = resolve("""
        {
          "hotkeys": {
            "app:a": "hyper+1", "app:b": "rcmd", "app:c": "double:cmd", "app:d": "both:shift",
            "app:e": "f13", "app:f": null
          }
        }
        """)
        #expect(resolution.issues.isEmpty)
        let hotkeys = resolution.settings?.hotkeys ?? [:]
        #expect(hotkeys[ItemID(rawValue: "app:a")] == combo([], .character("1"), hyper: true))
        #expect(hotkeys[ItemID(rawValue: "app:b")] == .modifierTap([SidedModifier(.command, side: .right)]))
        #expect(hotkeys[ItemID(rawValue: "app:c")] == .doubleTap(SidedModifier(.command)))
        #expect(hotkeys[ItemID(rawValue: "app:d")] == .bothSides(.shift))
        #expect(hotkeys[ItemID(rawValue: "app:e")] == combo([], .named(.f13)))
        #expect(hotkeys[ItemID(rawValue: "app:f")] == nil)
        #expect(hotkeys.count == 5)
    }

    @Test("a bad hotkey is dropped with a warning")
    func badHotkey() {
        let resolution = resolve(#"{ "hotkeys": { "app:a": "k", "app:b": true } }"#)
        #expect(resolution.settings?.hotkeys.isEmpty == true)
        #expect(warns(resolution, "hotkeys.app:a: \"k\" is not a hotkey"))
        #expect(warns(resolution, "hotkeys.app:b: true is not a hotkey"))
    }

    @Test("two items on the same hotkey: the later id is dropped and both are named")
    func duplicateHotkeys() {
        let resolution = resolve("""
        { "hotkeys": { "window:leftHalf": "cmd+1", "app:com.google.Chrome": "command+1", "app:com.apple.Safari": "cmd+2" } }
        """)
        #expect(resolution.settings?.hotkeys == [chrome: combo(.command, .character("1")), safari: combo(.command, .character("2"))])
        #expect(warnings(resolution) == ["hotkeys.window:leftHalf: \"cmd+1\" is already the hotkey of app:com.google.Chrome; dropped."])
    }

    @Test("hyper is expanded before comparing, following includeShift")
    func duplicateHyperHotkeys() {
        let withShift = resolve(#"{ "hotkeys": { "app:a": "hyper+k", "app:b": "ctrl+opt+shift+cmd+k", "app:c": "ctrl+opt+cmd+k" } }"#)
        #expect(withShift.settings?.hotkeys.keys.sorted() == [ItemID(rawValue: "app:a"), ItemID(rawValue: "app:c")])
        #expect(warns(withShift, "hotkeys.app:b: \"ctrl+opt+shift+cmd+k\" is already the hotkey of app:a; dropped."))

        let withoutShift = resolve("""
        { "hyperKey": { "includeShift": false },
          "hotkeys": { "app:a": "hyper+k", "app:b": "ctrl+opt+shift+cmd+k", "app:c": "ctrl+opt+cmd+k" } }
        """)
        #expect(withoutShift.settings?.hotkeys.keys.sorted() == [ItemID(rawValue: "app:a"), ItemID(rawValue: "app:b")])
        #expect(warns(withoutShift, "hotkeys.app:c: \"ctrl+opt+cmd+k\" is already the hotkey of app:a; dropped."))
    }

    @Test("an item hotkey equal to launcher.hotkey is dropped")
    func clashWithLauncher() {
        let defaultLauncher = resolve(#"{ "hotkeys": { "app:a": "cmd+space" } }"#)
        #expect(defaultLauncher.settings?.hotkeys.isEmpty == true)
        #expect(warnings(defaultLauncher) == ["hotkeys.app:a: \"cmd+space\" is launcher.hotkey; dropped."])

        let movedLauncher = resolve(#"{ "launcher": { "hotkey": "opt+space" }, "hotkeys": { "app:a": "cmd+space", "app:b": "alt+space" } }"#)
        #expect(movedLauncher.settings?.hotkeys == [ItemID(rawValue: "app:a"): combo(.command, .named(.space))])
        #expect(warns(movedLauncher, "hotkeys.app:b: \"alt+space\" is launcher.hotkey; dropped."))
    }

    @Test("launcher.hotkey null means no launcher hotkey and frees its combination")
    func launcherHotkeyNull() {
        let resolution = resolve(#"{ "launcher": { "hotkey": null }, "hotkeys": { "app:a": "cmd+space" } }"#)
        #expect(resolution.issues.isEmpty)
        #expect(resolution.settings?.launcher.hotkey == nil)
        #expect(resolution.settings?.hotkeys == [ItemID(rawValue: "app:a"): combo(.command, .named(.space))])
        #expect(resolution.settings?.hotkeyBindings == [HotkeyBinding(spec: combo(.command, .named(.space)), target: .item(ItemID(rawValue: "app:a")))])
    }

    @Test("a bad launcher.hotkey keeps the default")
    func badLauncherHotkey() {
        let resolution = resolve(#"{ "launcher": { "hotkey": 5 } }"#)
        #expect(resolution.settings?.launcher.hotkey == LauncherSettings().hotkey)
        #expect(warns(resolution, "launcher.hotkey: 5 is not a hotkey"))
    }

    // MARK: Aliases

    @Test("aliases are lowercased; invalid characters drop the alias")
    func aliasRules() {
        let resolution = resolve(#"{ "aliases": { "app:a": "GC", "app:b": "g-c", "app:c": "my app 2", "app:d": "", "app:e": 3, "app:f": null } }"#)
        #expect(resolution.settings?.aliases == [ItemID(rawValue: "app:a"): "gc", ItemID(rawValue: "app:c"): "my app 2"])
        #expect(warns(resolution, "aliases.app:b: \"g-c\" may only contain a–z, 0–9 and spaces; dropped."))
        #expect(warns(resolution, "aliases.app:d: \"\" is empty; dropped."))
        #expect(warns(resolution, "aliases.app:e: 3 is not an alias string or null; dropped."))
        #expect(warnings(resolution).count == 3)
    }

    @Test("duplicate aliases warn and both are kept")
    func duplicateAliases() {
        let resolution = resolve(#"{ "aliases": { "app:com.google.Chrome": "gc", "app:com.apple.Safari": "GC" } }"#)
        #expect(resolution.settings?.aliases == [chrome: "gc", safari: "gc"])
        #expect(warnings(resolution) == ["aliases.app:com.google.Chrome: \"gc\" is also the alias of app:com.apple.Safari."])
    }

    // MARK: Quicklinks

    @Test("quicklink ids must match a–z, 0–9 and dashes")
    func quicklinkIDPattern() {
        let resolution = resolve("""
        { "quicklinks": [
          { "id": "my-link-2", "name": "A", "link": "https://a.com" },
          { "id": "My Link", "name": "B", "link": "https://b.com" },
          { "name": "C", "link": "https://c.com" },
          { "id": "", "name": "D", "link": "https://d.com" }
        ] }
        """)
        #expect(resolution.settings?.quicklinks.map { $0.id } == ["my-link-2"])
        #expect(warns(resolution, "quicklinks[1].id: \"My Link\" is not an id"))
        #expect(warns(resolution, "quicklinks[2].id: missing is not an id"))
        #expect(warns(resolution, "quicklinks[3].id: \"\" is not an id"))
    }

    @Test("a repeated quicklink id drops the later quicklink")
    func quicklinkUniqueness() {
        let resolution = resolve("""
        { "quicklinks": [
          { "id": "a", "name": "First", "link": "https://1.com" },
          { "id": "a", "name": "Second", "link": "https://2.com" }
        ] }
        """)
        #expect(resolution.settings?.quicklinks.map { $0.name } == ["First"])
        #expect(warnings(resolution) == ["quicklinks[1].id: \"a\" is already the id of quicklinks[0]; quicklink dropped."])
    }

    @Test("a quicklink without name or link is dropped; bad optional fields are ignored")
    func quicklinkRequiredFields() {
        let resolution = resolve("""
        { "quicklinks": [
          { "id": "a", "link": "https://a.com" },
          { "id": "b", "name": "B", "link": "  " },
          { "id": "c", "name": "C", "link": "~/Notes", "openWith": 3, "icon": null },
          "d"
        ] }
        """)
        #expect(resolution.settings?.quicklinks == [Quicklink(id: "c", name: "C", link: "~/Notes")])
        #expect(warns(resolution, "quicklinks[0].name: missing is not a non-empty string; quicklink dropped."))
        #expect(warns(resolution, "quicklinks[1].link: \"  \" is not a non-empty string; quicklink dropped."))
        #expect(warns(resolution, "quicklinks[2].openWith: 3 is not"))
        #expect(warns(resolution, "quicklinks[3]: \"d\" is not an object; dropped."))
        #expect(warnings(resolution).count == 4)
    }

    // MARK: Hyper key

    @Test("quickPress other than nothing needs the Caps Lock trigger")
    func quickPressWithoutCapsLock() {
        let noTrigger = resolve(#"{ "hyperKey": { "quickPress": "toggleCapsLock" } }"#)
        #expect(noTrigger.settings?.hyperKey.quickPress == .nothing)
        #expect(warnings(noTrigger) == ["hyperKey.quickPress: \"toggleCapsLock\" needs trigger \"capsLock\"; kept \"nothing\"."])

        let rightCommand = resolve(#"{ "hyperKey": { "trigger": "rightCommand", "quickPress": "escape" } }"#)
        #expect(rightCommand.settings?.hyperKey == HyperKeySettings(trigger: .rightCommand, quickPress: .nothing))
        #expect(warns(rightCommand, "needs trigger \"capsLock\""))

        let capsLock = resolve(#"{ "hyperKey": { "trigger": "capsLock", "quickPress": "toggleCapsLock" } }"#)
        #expect(capsLock.issues.isEmpty)
        #expect(capsLock.settings?.hyperKey.quickPress == .toggleCapsLock)
    }

    @Test("a bad hyperKey trigger keeps null")
    func badTrigger() {
        let resolution = resolve(#"{ "hyperKey": { "trigger": "leftCommand" } }"#)
        #expect(resolution.settings?.hyperKey.trigger == nil)
        #expect(warns(resolution, "hyperKey.trigger: \"leftCommand\" is not one of \"capsLock\""))
    }

    // MARK: Ranges, enums, booleans, integers

    @Test("gap and popToRootSeconds clamp into their ranges with a warning")
    func clamping() {
        let resolution = resolve(#"{ "launcher": { "popToRootSeconds": 5000 }, "windowManagement": { "gap": -4 } }"#)
        #expect(resolution.settings?.launcher.popToRootSeconds == 3600)
        #expect(resolution.settings?.windowManagement.gap == 0)
        #expect(warnings(resolution) == [
            "launcher.popToRootSeconds: 5000 is outside 0–3600; clamped to 3600.",
            "windowManagement.gap: -4 is outside 0–64; clamped to 0.",
        ])

        let edges = resolve(#"{ "launcher": { "popToRootSeconds": 3600 }, "windowManagement": { "gap": 64 } }"#)
        #expect(edges.issues.isEmpty)
        #expect(edges.settings?.windowManagement.gap == 64)
        let over = resolve(#"{ "windowManagement": { "gap": 65 } }"#)
        #expect(over.settings?.windowManagement.gap == 64)
    }

    @Test("enum values must be exact spellings; bad ones keep the default and list the allowed values")
    func enumValues() {
        let resolution = resolve(#"{ "launcher": { "screen": "WithMouse", "navigation": "vim" }, "windowManagement": { "halves": "cycle" } }"#)
        #expect(resolution.settings?.launcher.screen == .withMouse)
        #expect(resolution.settings?.launcher.navigation == .vim)
        #expect(resolution.settings?.windowManagement.halves == .stay)
        #expect(warns(resolution, "launcher.screen: \"WithMouse\" is not one of \"withMouse\", \"withActiveWindow\", \"primary\"; kept \"withMouse\"."))
        #expect(warns(resolution, "windowManagement.halves: \"cycle\" is not one of \"stay\", \"cycleSizes\", \"moveToDisplay\"; kept \"stay\"."))
    }

    @Test("booleans accept only JSON booleans")
    func booleansStrict() {
        let resolution = resolve(#"{ "launcher": { "closeOnFocusLoss": 0 }, "app": { "startAtLogin": "false", "showMenuBarIcon": false } }"#)
        #expect(resolution.settings?.launcher.closeOnFocusLoss == true)
        #expect(resolution.settings?.app == AppBehaviorSettings(startAtLogin: true, showMenuBarIcon: false))
        #expect(warns(resolution, "launcher.closeOnFocusLoss: 0 is not true or false; kept true."))
        #expect(warns(resolution, "app.startAtLogin: \"false\" is not true or false; kept true."))
    }

    @Test("integers accept only whole numbers")
    func integersStrict() {
        let resolution = resolve(#"{ "launcher": { "popToRootSeconds": 1.5 }, "windowManagement": { "gap": true } }"#)
        #expect(resolution.settings?.launcher.popToRootSeconds == 90)
        #expect(resolution.settings?.windowManagement.gap == 0)
        #expect(warns(resolution, "launcher.popToRootSeconds: 1.5 is not a whole number of seconds; kept 90."))
        #expect(warns(resolution, "windowManagement.gap: true is not a whole number of points; kept 0."))

        let wholeDouble = resolve(#"{ "windowManagement": { "gap": 12.0 } }"#)
        #expect(wholeDouble.issues.isEmpty)
        #expect(wholeDouble.settings?.windowManagement.gap == 12)
    }

    @Test("folder lists drop non-strings and empty entries")
    func directories() {
        let resolution = resolve(#"{ "scriptDirectories": ["~/s", 1, ""], "applicationDirectories": "~/Apps" }"#)
        #expect(resolution.settings?.scriptDirectories == ["~/s"])
        #expect(resolution.settings?.applicationDirectories == [])
        #expect(warns(resolution, "scriptDirectories[1]: 1 is not a folder path; dropped."))
        #expect(warns(resolution, "scriptDirectories[2]: \"\" is not a folder path; dropped."))
        #expect(warns(resolution, "applicationDirectories: \"~/Apps\" is not an array of folder paths; kept none."))
    }
}
