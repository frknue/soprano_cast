import AppKit
import Testing
@testable import SopranoCastCore

struct SopranoThemeSettingsTests {
    @Test("theme and appearance are read from JSONC, everything else ignored")
    func readsThemeAndAppearance() {
        let text = """
        {
          // Soprano's own keys stay unread
          "theme": "folio",
          "appearance": "dark",
          "statusBar": { "uptime": true },
        }
        """
        #expect(SopranoThemeSettings.read(text: text) == SopranoThemeSettings(theme: "folio", appearance: .dark))
    }

    @Test("a missing or unknown appearance follows the system; an unknown theme id is kept as written")
    func defaults() {
        #expect(SopranoThemeSettings.read(text: "{}") == SopranoThemeSettings(theme: nil, appearance: .system))
        #expect(SopranoThemeSettings.read(text: #"{ "theme": "mission-control", "appearance": "sepia" }"#)
            == SopranoThemeSettings(theme: "mission-control", appearance: .system))
        #expect(SopranoThemeSettings.read(text: #"{ "theme": 3, "appearance": "light" }"#)
            == SopranoThemeSettings(theme: nil, appearance: .light))
    }

    @Test("a document that is not a JSON object reads as nil")
    func notAnObject() {
        #expect(SopranoThemeSettings.read(text: "[]") == nil)
        #expect(SopranoThemeSettings.read(text: "{ \"theme\": ") == nil)
    }
}
