import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct LauncherModelBuilderTests {
    private let chrome = LauncherTestItems.chrome
    private let greet = LauncherTestItems.greet

    private func model(
        query: String = "",
        sections: [ResultSection],
        selectedIndex: Int? = 0,
        arguments: [ArgumentSpec] = [],
        argumentValues: [String] = [],
        focus: LauncherFocus = .query,
        toast: LauncherToast? = nil,
        overlay: OverlayViewModel = .none,
        settings: CastSettings = CastSettings()
    ) -> LauncherViewModel {
        LauncherModelBuilder.model(
            theme: AppTheme.missionControl,
            query: query,
            sections: sections,
            selectedIndex: selectedIndex,
            arguments: arguments,
            argumentValues: argumentValues,
            focus: focus,
            toast: toast,
            overlay: overlay,
            settings: settings,
            icon: { _ in NSImage(size: NSSize(width: 24, height: 24)) }
        )
    }

    private func results(_ items: [CastItem]) -> [ResultSection] {
        [ResultSection(kind: .results, rows: items.map { RankedItem(item: $0, score: 0) })]
    }

    @Test("rows show their kind's label; calculator rows their expression and scripts their package")
    func accessories() {
        let calculator = CastItem(id: .calculatorResult, title: "4", subtitle: "2+2", icon: .glyph(.calculator))
        let built = model(query: "x", sections: results([chrome, calculator, greet]))
        let rows = built.sections.flatMap { $0.rows }
        #expect(rows.map { $0.accessory } == ["Application", "2+2", "Demo"])
        #expect(rows.map { $0.subtitle } == ["/Applications", "", ""])
    }

    @Test("rows carry the alias badge and the hotkey keycaps from the settings")
    func aliasAndKeycaps() {
        var settings = CastSettings()
        settings.aliases[chrome.id] = "gc"
        let hotkey = HotkeySpec.combo(HotkeyCombo(modifiers: .command, key: .character("1")))
        settings.hotkeys[chrome.id] = hotkey
        let rows = model(sections: results([chrome, greet]), settings: settings).sections.flatMap { $0.rows }
        #expect(rows.map { $0.alias } == ["gc", nil])
        #expect(rows[0].hotkeyKeys == hotkey.keycaps)
        #expect(rows[1].hotkeyKeys.isEmpty)
    }

    @Test("matched title characters become highlight ranges")
    func highlights() {
        let title = chrome.title
        let range = title.range(of: "Chrome")!
        let ranked = RankedItem(item: chrome, score: 0, titleRanges: [range])
        let built = model(query: "chrome", sections: [ResultSection(kind: .results, rows: [ranked])])
        #expect(built.sections.first?.rows.first?.titleHighlights == [NSRange(location: 7, length: 6)])
    }

    @Test("the footer names the selection's primary action and offers actions")
    func footer() {
        let built = model(sections: results([chrome]), toast: LauncherToast(text: "Saved", isError: true))
        #expect(built.footer.primaryTitle == "Open Application")
        #expect(built.footer.showsActions)
        #expect(built.footer.toast == "Saved")
        #expect(built.footer.toastIsError)

        let empty = model(sections: [], selectedIndex: nil)
        #expect(empty.footer.primaryTitle == nil)
        #expect(!empty.footer.showsActions)
    }

    @Test("the empty text depends on whether there is a query")
    func emptyTexts() {
        #expect(model(query: "", sections: [], selectedIndex: nil).emptyText == "Type to search apps and commands")
        #expect(model(query: "zzz", sections: [], selectedIndex: nil).emptyText == "No results")
        #expect(model(query: "x", sections: results([chrome])).emptyText == nil)
    }

    @Test("sections are titled by their kind and the placeholder is Raycast's")
    func sectionsAndPlaceholder() {
        let built = model(sections: results([chrome]))
        #expect(built.sections.map { $0.title } == ["results"])
        #expect(built.placeholder == "Search for apps and commands…")
    }

    @Test("the fallbacks header and rows quote the query; the rows keep their kind label")
    func fallbackSection() {
        let google = CastItem(
            id: LauncherTestItems.searchGoogle, title: "Search Google", subtitle: "Soprano Cast",
            icon: .glyph(.magnifier), arguments: [ArgumentSpec(name: "Query", placeholder: "Query")]
        )
        let sections = results([chrome]) + [ResultSection(kind: .fallbacks, rows: [RankedItem(item: google, score: 0)])]
        let built = model(query: " gogo ", sections: sections)
        #expect(built.sections.map { $0.title } == ["results", "use “gogo” with…"])
        let row = built.sections[1].rows[0]
        #expect(row.subtitle == "“gogo”")
        #expect(row.accessory == ItemKind.castCommand.label)
    }

    @Test("argument fields show placeholders, secure text and dropdown titles")
    func argumentFields() {
        let specs = [
            ArgumentSpec(name: "name", placeholder: ""),
            ArgumentSpec(name: "token", placeholder: "Token", kind: .password, isOptional: true),
            ArgumentSpec(name: "size", placeholder: "Size", kind: .dropdown([
                ArgumentSpec.DropdownOption(title: "Small", value: "s"),
                ArgumentSpec.DropdownOption(title: "Large", value: "l"),
            ])),
        ]
        let fields = model(sections: results([greet]), arguments: specs, argumentValues: ["Ada", "", "l"]).arguments
        #expect(fields.map { $0.placeholder } == ["name", "Token", "Size"])
        #expect(fields.map { $0.value } == ["Ada", "", "Large"])
        #expect(fields.map { $0.isSecure } == [false, true, false])
        #expect(fields.map { $0.isOptional } == [false, true, false])
        #expect(fields[2].options == ["Small", "Large"])
        #expect(fields[0].options == nil)
    }

    @Test("overlays with a text field take the focus; the others take it away")
    func overlayFocus() {
        let sections = results([greet])
        let specs = greet.arguments
        #expect(model(sections: sections, arguments: specs, focus: .argument(0)).focus == .argument(0))
        let panel = OverlayViewModel.actionPanel(title: "Greet", query: "", rows: [], selectedIndex: nil)
        #expect(model(sections: sections, focus: .query, overlay: panel).focus == .overlay)
        let confirmation = OverlayViewModel.confirmation(title: "Greet", message: "Are you sure?", confirmTitle: "Greet")
        #expect(model(sections: sections, focus: .query, overlay: confirmation).focus == LauncherFocus.none)
    }

    @Test("action rows show their shortcut keycaps and destructive style")
    func actionRows() {
        let actions = [
            ItemAction(id: .copyPath, title: "Copy Path", shortcut: HotkeyCombo(modifiers: [.shift, .command], key: .character("c"))),
            ItemAction(id: .disableCommand, title: "Disable Command", isDestructive: true),
            ItemAction(id: .setHotkey, title: "Set Hotkey…"),
        ]
        let rows = LauncherModelBuilder.actionRows(actions)
        #expect(rows[0].keys == ["⇧", "⌘", "C"])
        #expect(rows.map { $0.isDestructive } == [false, true, false])
        #expect(rows[2].keys.isEmpty)
    }

    @Test("the recorder overlay carries the hint and the conflict line")
    func recorderOverlay() {
        let overlay = LauncherModelBuilder.recorder(
            itemTitle: "Google Chrome", keys: ["⌘", "1"],
            conflict: LauncherModelBuilder.conflictText(ownerTitle: "Slack"), countdown: 0.5
        )
        guard case .recorder(let title, let keys, let conflict, let countdown, let hint) = overlay else {
            Issue.record("not a recorder")
            return
        }
        #expect(title == "Google Chrome")
        #expect(keys == ["⌘", "1"])
        #expect(conflict == "Used by Slack")
        #expect(countdown == 0.5)
        #expect(hint == "⌫ clear · ⎋ cancel · ↵ save")
    }
}
