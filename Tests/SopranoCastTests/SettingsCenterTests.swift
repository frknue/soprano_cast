import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct SettingsCenterTests {
    /// A settings.json path inside a fresh temporary directory that does not exist yet.
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("soprano-cast-settings-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private func removeDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private let chrome = ItemID(rawValue: "app:com.google.Chrome")

    @Test("the settings path honors SOPRANO_CAST_CONFIG, then XDG_CONFIG_HOME, then ~/.config")
    func settingsPathResolution() {
        let override = SettingsFile.url(environment: ["SOPRANO_CAST_CONFIG": "/opt/dots/cast.json", "XDG_CONFIG_HOME": "/opt/xdg"])
        let xdg = SettingsFile.url(environment: ["XDG_CONFIG_HOME": "/opt/xdg"])
        let home = SettingsFile.url(environment: [:])

        #expect(override.path == "/opt/dots/cast.json")
        #expect(xdg.path == "/opt/xdg/soprano-cast/settings.json")
        #expect(home.path.hasSuffix("/.config/soprano-cast/settings.json"))
    }

    @Test("a missing settings file is created from the template and resolves to the defaults")
    func createsMissingFileFromTemplate() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)

        center.start(watching: false)

        #expect(try SettingsFile.read(at: url) == SettingsTemplate.text)
        #expect(center.settings == .defaults)
        #expect(center.issues.isEmpty)
    }

    @Test("an edited file applies on reload and notifies observers once per change")
    func reloadAppliesEdits() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)
        let owner = NSObject()
        var notifications = 0
        center.addObserver(owner) { notifications += 1 }

        try SettingsFile.write(
            #"{ "launcher": { "popToRootSeconds": 30 }, "app": { "showMenuBarIcon": false } }"#,
            to: url
        )
        center.reload()

        #expect(center.settings.launcher.popToRootSeconds == 30)
        #expect(center.settings.app.showMenuBarIcon == false)
        #expect(notifications == 1)

        center.reload()
        #expect(notifications == 1)
        withExtendedLifetime(owner) {}
    }

    @Test("a document that does not parse keeps the last good settings and reports an error")
    func invalidDocumentKeepsLastGoodSettings() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)
        try SettingsFile.write(#"{ "launcher": { "popToRootSeconds": 30 } }"#, to: url)
        center.reload()

        try SettingsFile.write(#"{ "launcher": { "popToRootSeconds": "#, to: url)
        center.reload()

        #expect(center.settings.launcher.popToRootSeconds == 30)
        #expect(center.issues.contains { $0.severity == .error })

        try SettingsFile.write(#"{ "launcher": { "popToRootSeconds": 45 } }"#, to: url)
        center.reload()

        #expect(center.settings.launcher.popToRootSeconds == 45)
        #expect(!center.issues.contains { $0.severity == .error })
    }

    @Test("set and remove edits keep the file's comments and apply at once")
    func editsPreserveComments() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        try SettingsFile.write(
            """
            // My launcher.
            {
              // Follow Soprano.
              "theme": "soprano"
            }

            """,
            to: url
        )
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)

        try center.edit(.set("gc", ["aliases", chrome.rawValue]))
        try center.edit(.set(false, ["app", "startAtLogin"]))

        #expect(center.settings.aliases[chrome] == "gc")
        #expect(center.settings.app.startAtLogin == false)

        try center.edit(.remove(["aliases", chrome.rawValue]))

        let text = try SettingsFile.read(at: url)
        #expect(text.contains("// My launcher."))
        #expect(text.contains("// Follow Soprano."))
        #expect(center.settings.aliases[chrome] == nil)
        #expect(center.settings.app.startAtLogin == false)
        #expect(center.settings.theme == "soprano")
    }

    @Test("an edit notifies observers so the launcher and hotkeys refresh")
    func editNotifiesObservers() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)
        let owner = NSObject()
        var notifications = 0
        center.addObserver(owner) { notifications += 1 }

        try center.edit(.set([chrome.rawValue], ["favorites"]))

        #expect(center.settings.favorites == [chrome])
        #expect(notifications == 1)
        withExtendedLifetime(owner) {}
    }
}
