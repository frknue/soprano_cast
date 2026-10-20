import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

struct SettingsPaneScanTests {
    /// A scanned tree: `Extensions` holds `.appex` bundles, `PreferencePanes` `.prefPane` ones.
    private struct Tree {
        let root: URL
        var extensions: String { root.appendingPathComponent("Extensions").path }
        var preferencePanes: String { root.appendingPathComponent("PreferencePanes").path }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeTree() throws -> Tree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsPaneScanTests-\(UUID().uuidString)", isDirectory: true)
        let tree = Tree(root: root)
        for folder in [tree.extensions, tree.preferencePanes] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        return tree
    }

    /// A settings extension's Info.plist System Settings opens by URL.
    private func extensionInfo(_ bundleID: String, name: String) -> [String: Any] {
        [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "EXAppExtensionAttributes": [
                "EXExtensionPointIdentifier": SettingsPanes.extensionPoint,
                "SettingsExtensionAttributes": ["allowsXAppleSystemPreferencesURLScheme": true],
            ] as [String: Any],
        ]
    }

    /// Writes `folder/name` with Contents/Info.plist, an optional binary
    /// Resources/InfoPlist.loctable and optional Resources/<locale>.lproj/InfoPlist.strings.
    @discardableResult
    private func makeBundle(
        _ name: String,
        in folder: String,
        info: [String: Any],
        loctable: [String: Any]? = nil,
        strings: [String: String] = [:]
    ) throws -> String {
        let path = (folder as NSString).appendingPathComponent(name)
        let contents = URL(fileURLWithPath: path).appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let loctable {
            try PropertyListSerialization.data(fromPropertyList: loctable, format: .binary, options: 0)
                .write(to: resources.appendingPathComponent("InfoPlist.loctable"))
        }
        for (locale, text) in strings {
            let lproj = resources.appendingPathComponent("\(locale).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: lproj.appendingPathComponent("InfoPlist.strings"))
        }
        return path
    }

    /// Bluetooth (loctable with LocProvenance), Sound (plus a prefPane with its id), two
    /// "Amp" panes, a prefPane named by de.lproj strings, a lowercase .prefpane, and files
    /// that aren't bundles of the scanned kind.
    private func makePanes() throws -> Tree {
        let tree = try makeTree()
        try makeBundle(
            "Bluetooth.appex",
            in: tree.extensions,
            info: extensionInfo("com.example.bluetooth", name: "BluetoothSettingsExtension"),
            loctable: [
                "LocProvenance": ["de": 1, "en": 1],
                "en": ["CFBundleDisplayName": "Bluetooth"],
                "de": ["CFBundleDisplayName": "Blauzahn"],
            ]
        )
        try makeBundle("Sound.appex", in: tree.extensions, info: extensionInfo("com.example.sound", name: "Sound"))
        try makeBundle(
            "OldSound.prefPane",
            in: tree.preferencePanes,
            info: ["CFBundleIdentifier": "com.example.sound", "CFBundleName": "Old Sound"]
        )
        // File order (One, Two) is the reverse of id order (z, a).
        try makeBundle("AmpOne.prefPane", in: tree.preferencePanes, info: ["CFBundleIdentifier": "com.example.z", "CFBundleName": "Amp"])
        try makeBundle("AmpTwo.prefPane", in: tree.preferencePanes, info: ["CFBundleIdentifier": "com.example.a", "CFBundleName": "Amp"])
        try makeBundle(
            "Legacy.prefPane",
            in: tree.preferencePanes,
            info: ["CFBundleIdentifier": "com.example.legacy", "CFBundleName": "Legacy"],
            strings: ["de": "\"CFBundleDisplayName\" = \"Altlast\";\n"]
        )
        try makeBundle("lower.prefpane", in: tree.preferencePanes, info: ["CFBundleIdentifier": "com.example.lower", "CFBundleName": "Lower"])
        // Not scanned: wrong extension in either folder, a hidden bundle, a plain file.
        try makeBundle("Stray.prefPane", in: tree.extensions, info: ["CFBundleIdentifier": "com.example.stray", "CFBundleName": "Stray"])
        try makeBundle("Widget.appex", in: tree.preferencePanes, info: extensionInfo("com.example.widget", name: "Widget"))
        try makeBundle(".Hidden.appex", in: tree.extensions, info: extensionInfo("com.example.hidden", name: "Hidden"))
        try Data("notes".utf8).write(to: URL(fileURLWithPath: tree.extensions).appendingPathComponent("notes.txt"))
        return tree
    }

    private func collect(_ tree: Tree) -> [CastItem] {
        LiveSettingsPaneCatalog.collect(
            extensionDirectories: [tree.extensions],
            preferencePaneDirectories: [tree.preferencePanes],
            facts: SettingsPaneFacts(),
            preferredLanguages: ["de-DE"],
            preference: { _, _ in nil }
        )
    }

    private func pane(_ bundleID: String, in items: [CastItem]) -> CastItem? {
        items.first { $0.id == ItemID(kind: .settingsPane, key: bundleID) }
    }

    @Test("An extension is named from its loctable in the user's language, with the English name as a keyword")
    func extensionNamedFromLoctable() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        let bluetooth = try #require(pane("com.example.bluetooth", in: collect(tree)))
        #expect(bluetooth.title == "Blauzahn")
        #expect(bluetooth.keywords == ["Bluetooth"])
        #expect(bluetooth.subtitle == SettingsPanes.subtitle)
        #expect(bluetooth.icon == .file(path: (tree.extensions as NSString).appendingPathComponent("Bluetooth.appex")))
    }

    @Test("A loctable's LocProvenance entry is not read as a locale")
    func provenanceIsNotALocale() throws {
        let tree = try makePanes()
        defer { tree.remove() }
        let path = (tree.extensions as NSString).appendingPathComponent("Bluetooth.appex")

        let tables = LiveSettingsPaneCatalog.localizedTables(named: "InfoPlist", inBundleAt: path)
        #expect(Set(tables.keys) == ["de", "en"])
        #expect(tables["de"]?["CFBundleDisplayName"] as? String == "Blauzahn")
    }

    @Test("A preference pane without a loctable is named from its lproj InfoPlist.strings")
    func prefPaneNamedFromLprojStrings() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        #expect(pane("com.example.legacy", in: collect(tree))?.title == "Altlast")
    }

    @Test("A bundle without any localized strings has no tables")
    func noLocalizedStrings() throws {
        let tree = try makePanes()
        defer { tree.remove() }
        let path = (tree.extensions as NSString).appendingPathComponent("Sound.appex")

        #expect(LiveSettingsPaneCatalog.localizedTables(named: "InfoPlist", inBundleAt: path).isEmpty)
    }

    @Test("A lowercase .prefpane is found and opens as a file")
    func lowercasePrefPaneOpensByFile() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        let lower = try #require(pane("com.example.lower", in: collect(tree)))
        #expect(lower.title == "Lower")
        let path = (tree.preferencePanes as NSString).appendingPathComponent("lower.prefpane")
        #expect(SettingsPanes.target(for: lower) == .file(path))
    }

    @Test("Extensions open by System Settings URL")
    func extensionOpensByURL() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        let sound = try #require(pane("com.example.sound", in: collect(tree)))
        #expect(SettingsPanes.target(for: sound) == .url("x-apple.systempreferences:com.example.sound"))
    }

    @Test("A preference pane with an extension's bundle id is dropped in favor of the extension")
    func extensionWinsOverPrefPane() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        let sounds = collect(tree).filter { $0.id == ItemID(kind: .settingsPane, key: "com.example.sound") }
        #expect(sounds.count == 1)
        #expect(sounds.first?.title == "Sound")
        #expect(sounds.first?.icon == .file(path: (tree.extensions as NSString).appendingPathComponent("Sound.appex")))
    }

    @Test("Panes are sorted by title, then by id")
    func sortedByTitleThenID() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        #expect(collect(tree).map(\.id.key) == [
            "com.example.legacy", // Altlast
            "com.example.a", // Amp
            "com.example.z", // Amp
            "com.example.bluetooth", // Blauzahn
            "com.example.lower", // Lower
            "com.example.sound", // Sound
        ])
    }

    @Test("Hidden bundles, plain files and bundles of the other kind in a folder are ignored")
    func nonBundlesIgnored() throws {
        let tree = try makePanes()
        defer { tree.remove() }

        let keys = Set(collect(tree).map(\.id.key))
        for ignored in ["com.example.stray", "com.example.widget", "com.example.hidden"] {
            #expect(!keys.contains(ignored))
        }
        #expect(keys.count == 6)
    }

    @Test("Missing folders contribute no panes")
    func missingFoldersEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsPaneScanTests-missing-\(UUID().uuidString)").path
        let items = LiveSettingsPaneCatalog.collect(
            extensionDirectories: [missing],
            preferencePaneDirectories: [missing],
            facts: SettingsPaneFacts(),
            preferredLanguages: ["en"],
            preference: { _, _ in nil }
        )
        #expect(items.isEmpty)
    }
}
