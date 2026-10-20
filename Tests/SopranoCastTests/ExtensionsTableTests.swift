import AppKit
import Testing
@testable import SopranoCastCore

struct ExtensionsTableTests {
    private func item(_ raw: String, _ title: String, subtitle: String = "") -> CastItem {
        CastItem(id: ItemID(rawValue: raw), title: title, subtitle: subtitle, icon: .glyph(.gear))
    }

    private var items: [CastItem] {
        [
            item("app:com.tinyspeck.slackmacgap", "Slack", subtitle: "/Applications"),
            item("window:leftHalf", "Left Half"),
            item("app:com.google.Chrome", "Google Chrome", subtitle: "/Applications"),
            item("calculator:result", "4"),
            item("cast:quit", "Quit Soprano Cast"),
            item("system:lockScreen", "Lock Screen"),
            item("pane:com.apple.BluetoothSettings", "Bluetooth", subtitle: "System Settings"),
            item("app:com.apple.mail", "Mail", subtitle: "/System/Applications"),
        ]
    }

    @Test("every group is listed in Raycast's order, titles sorted, without the calculator")
    func groupsInOrder() {
        let sections = ExtensionsTable.sections(items: items, settings: CastSettings())
        #expect(sections.map(\.group) == ExtensionGroup.allCases)
        #expect(sections[0].rows.map(\.item.title) == ["Google Chrome", "Mail", "Slack"])
        #expect(sections.first { $0.group == .quicklinks }?.rows.isEmpty == true)
        #expect(!sections.flatMap(\.rows).contains { $0.item.id == .calculatorResult })
        #expect(sections.first { $0.group == .system }?.rows.map(\.item.title) == ["Lock Screen"])
        #expect(sections.first { $0.group == .systemSettings }?.rows.map(\.item.title) == ["Bluetooth"])
    }

    @Test("rows carry their alias, hotkey, enabled, favorite and fallback state from settings")
    func rowsReflectSettings() {
        var settings = CastSettings()
        let chrome = ItemID(rawValue: "app:com.google.Chrome")
        let hotkey = HotkeySpec.combo(HotkeyCombo(modifiers: .command, key: .physical(0x12)))
        settings.aliases[chrome] = "gc"
        settings.hotkeys[chrome] = hotkey
        settings.disabled = [chrome]
        settings.favorites = [chrome]
        settings.fallbacks = [chrome]
        let row = ExtensionsTable.sections(items: items, settings: settings)[0].rows[0]
        #expect(row.item.id == chrome)
        #expect(row.alias == "gc")
        #expect(row.hotkey == hotkey)
        #expect(!row.isEnabled)
        #expect(row.isFavorite)
        #expect(row.isFallback)
        #expect(row.typeLabel == "Application")
    }

    @Test("a filter keeps rows matching every word in title, subtitle, alias, type or id, and drops empty groups")
    func filterMatchesEveryWord() {
        var settings = CastSettings()
        settings.aliases[ItemID(rawValue: "app:com.tinyspeck.slackmacgap")] = "chat"
        let byAlias = ExtensionsTable.sections(items: items, settings: settings, filter: "CHAT")
        #expect(byAlias.map(\.group) == [.applications])
        #expect(byAlias[0].rows.map(\.item.title) == ["Slack"])

        let bySubtitleAndType = ExtensionsTable.sections(items: items, settings: settings, filter: "system application")
        #expect(bySubtitleAndType.flatMap(\.rows).map(\.item.title) == ["Mail"])

        let byID = ExtensionsTable.sections(items: items, settings: settings, filter: "window:")
        #expect(byID.flatMap(\.rows).map(\.item.title) == ["Left Half"])
        #expect(ExtensionsTable.sections(items: items, settings: settings, filter: "nothing like this").isEmpty)
    }

    @Test("quicklink ids come from the name's letters and digits and never repeat an existing id")
    func quicklinkIDs() {
        #expect(QuicklinkID.make(for: "GitHub Repo", existing: []) == "github-repo")
        #expect(QuicklinkID.make(for: "  Über Café / Menü! ", existing: []) == "uber-cafe-menu")
        #expect(QuicklinkID.make(for: "🐙", existing: []) == "quicklink")
        #expect(QuicklinkID.make(for: "GitHub Repo", existing: ["github-repo", "github-repo-2"]) == "github-repo-3")
    }
}
