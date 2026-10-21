import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct ThemeCenterTests {
    /// The system appearance the center reads; tests flip it.
    @MainActor
    private final class SystemBox {
        var appearance: AppTheme.Appearance = .light
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("soprano-cast-theme-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Follow Soprano uses Soprano's theme and its pinned appearance, else the system's")
    func followsSopranoThemeAndAppearance() {
        let dark = SopranoThemeSettings(theme: "folio", appearance: .dark)
        #expect(ThemeCenter.resolve(themeID: "soprano", soprano: dark, system: .light).id == "folio-ink")
        let system = SopranoThemeSettings(theme: "folio", appearance: .system)
        #expect(ThemeCenter.resolve(themeID: "soprano", soprano: system, system: .light).id == "folio-paper")
        #expect(ThemeCenter.resolve(themeID: "soprano", soprano: system, system: .dark).id == "folio-ink")
        let nord = SopranoThemeSettings(theme: "nord", appearance: .light)
        #expect(ThemeCenter.resolve(themeID: "soprano", soprano: nord, system: .light).id == "nord")
    }

    @Test("a missing Soprano file or an unknown Soprano theme follows Folio and the system")
    func unknownSopranoThemeIsFolio() {
        #expect(ThemeCenter.resolve(themeID: "soprano", soprano: nil, system: .dark).id == "folio-ink")
        let old = SopranoThemeSettings(theme: "mission-control", appearance: .light)
        #expect(ThemeCenter.resolve(themeID: "soprano", soprano: old, system: .dark).id == "folio-paper")
    }

    @Test("Cast's own folio follows the system; pinned and third-party ids ignore it")
    func ownThemeIDs() {
        #expect(ThemeCenter.resolve(themeID: "folio", soprano: nil, system: .dark).id == "folio-ink")
        #expect(ThemeCenter.resolve(themeID: "folio-paper", soprano: nil, system: .dark).id == "folio-paper")
        #expect(ThemeCenter.resolve(themeID: "dracula", soprano: nil, system: .light).id == "dracula")
    }

    @Test("the known ids are folio, the pinned Folio palettes and the third-party themes, not mission-control")
    func knownIDs() {
        #expect(ThemeCenter.knownThemeIDs.isSuperset(of: ["folio", "folio-paper", "folio-ink", "nord"]))
        #expect(!ThemeCenter.knownThemeIDs.contains("mission-control"))
    }

    @Test("a system appearance switch re-resolves folio and notifies once; an unchanged palette stays quiet")
    func appearanceSwitchNotifiesOnlyWhenThePaletteChanges() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(#"{ "theme": "folio" }"#, to: url)
        let settings = SettingsCenter(fileURL: url)
        settings.start(watching: false)
        let system = SystemBox()
        let center = ThemeCenter(
            sopranoSettingsURL: url, settings: settings,
            systemAppearance: { system.appearance }, setApplicationAppearance: { _ in }
        )
        let owner = NSObject()
        var notifications = 0
        center.addObserver(owner) { notifications += 1 }
        center.start()
        #expect(center.theme.id == "folio-paper")

        system.appearance = .dark
        center.systemAppearanceDidChange()
        #expect(center.theme.id == "folio-ink")
        #expect(notifications == 1)

        center.systemAppearanceDidChange()
        #expect(notifications == 1)
        withExtendedLifetime(owner) {}
    }

    @Test("only a palette that follows macOS leaves the app appearance unset")
    func followsSystemRule() {
        #expect(ThemeCenter.followsSystem(themeID: "folio", soprano: nil))
        #expect(ThemeCenter.followsSystem(themeID: "mission-control", soprano: nil))
        #expect(!ThemeCenter.followsSystem(themeID: "folio-paper", soprano: nil))
        #expect(!ThemeCenter.followsSystem(themeID: "nord", soprano: nil))
        #expect(ThemeCenter.followsSystem(themeID: "soprano", soprano: nil))
        #expect(ThemeCenter.followsSystem(themeID: "soprano", soprano: SopranoThemeSettings(theme: "folio", appearance: .system)))
        #expect(!ThemeCenter.followsSystem(themeID: "soprano", soprano: SopranoThemeSettings(theme: "folio", appearance: .dark)))
        #expect(!ThemeCenter.followsSystem(themeID: "soprano", soprano: SopranoThemeSettings(theme: "dracula", appearance: .system)))
    }

    @Test("the app appearance is the pinned or third-party theme's, and unset while folio follows the system")
    func applicationAppearanceFollowsTheTheme() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try write(#"{ "theme": "folio" }"#, to: url)
        let settings = SettingsCenter(fileURL: url)
        settings.start(watching: false)
        var applied: [NSAppearance.Name?] = []
        let center = ThemeCenter(
            sopranoSettingsURL: url, settings: settings,
            systemAppearance: { .light }, setApplicationAppearance: { applied.append($0?.name) }
        )
        center.start()
        #expect(applied.last == .some(nil))

        try write(#"{ "theme": "nord" }"#, to: url)
        settings.reload()
        #expect(center.theme.id == "nord")
        #expect(applied.last == .darkAqua)

        try write(#"{ "theme": "folio-paper" }"#, to: url)
        settings.reload()
        #expect(applied.last == .aqua)

        try write(#"{ "theme": "folio" }"#, to: url)
        settings.reload()
        #expect(applied.last == .some(nil))
    }
}
