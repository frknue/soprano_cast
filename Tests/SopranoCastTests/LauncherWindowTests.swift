import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct LauncherWindowTests {
    /// An AppKit visible frame below a 33 pt menu bar.
    private let screen = CGRect(x: 0, y: 33, width: 1512, height: 949)

    init() {
        LauncherWindow.offscreen = true
    }

    @Test("presenting two sections shows every row and renders a screen-sized image at the given scale")
    func presentRendersScreenSizedSnapshot() throws {
        let window = LauncherWindow()
        window.present(model(), screenFrame: screen)

        #expect(window.isPresented)
        #expect(window.rowViews.count == 3)
        #expect(window.content.list.headerViews.map { $0.title } == ["favorites", "results"])
        let image = try #require(window.renderSnapshot(screenFrame: screen, scale: 2, backdrop: nil))
        #expect(image.width == 3024)
        #expect(image.height == 1898)
    }

    @Test("the panel is centered horizontally with its top edge a fifth of the display below the top")
    func panelSitsAFifthDown() {
        let window = LauncherWindow()
        window.present(model(), screenFrame: screen)

        // Top = 982 − 949 / 5 = 792.2; bottom = 792.2 − 474, rounded.
        #expect(window.panelFrame == CGRect(x: 381, y: 318, width: 750, height: 474))
        #expect(window.visibleRowCount == 9)
    }

    @Test("an update with a new selection reuses the row views and moves the selection and its hotkey keycaps")
    func selectionUpdateReusesRows() {
        let window = LauncherWindow()
        window.present(model(selectedIndex: 0), screenFrame: screen)
        let before = window.rowViews
        #expect(before.map { $0.isSelected } == [true, false, false])
        #expect(before[0].shownHotkeyKeys == ["⌘", "1"])

        window.update(model(selectedIndex: 2))

        #expect(window.rowViews.count == 3)
        #expect(zip(before, window.rowViews).allSatisfy { $0 === $1 })
        #expect(window.rowViews.map { $0.isSelected } == [false, false, true])
        #expect(window.rowViews[0].shownHotkeyKeys.isEmpty)
    }

    @Test("every overlay shows its view and renders")
    func everyOverlayRenders() throws {
        let window = LauncherWindow()
        window.present(model(), screenFrame: screen)
        let content = window.content

        window.update(model(overlay: .actionPanel(
            title: "Google Chrome",
            query: "",
            rows: [
                ActionRowViewModel(title: "Open Application", keys: ["↵"], isDestructive: false),
                ActionRowViewModel(title: "Quit Application", keys: ["⌃", "⌘", "Q"], isDestructive: true),
            ],
            selectedIndex: 0
        ), focus: .overlay))
        #expect(!content.actionPanel.isHidden)
        #expect(content.actionPanel.rowViews.map { $0.title } == ["Open Application", "Quit Application"])
        #expect(window.focusedView === content.actionPanel.filterField)
        #expect(window.renderSnapshot(screenFrame: screen, scale: 1, backdrop: nil) != nil)

        window.update(model(overlay: .recorder(
            itemTitle: "Google Chrome", keys: ["⌘", "1"], conflict: "Used by Safari", countdown: 0.5,
            hint: "⌫ clear · ⎋ cancel · ↵ save"
        ), focus: .none))
        #expect(content.actionPanel.isHidden)
        #expect(!content.recorder.isHidden)
        #expect(content.recorder.shownKeys == ["⌘", "1"])
        #expect(content.recorder.countdownWidth == (RecorderCardView.width - RecorderCardView.padding * 2) / 2)
        #expect(window.renderSnapshot(screenFrame: screen, scale: 1, backdrop: nil) != nil)

        window.update(model(overlay: .aliasEditor(itemTitle: "Google Chrome", text: "gc", error: nil), focus: .overlay))
        #expect(!content.aliasEditor.isHidden)
        #expect(content.aliasEditor.field.stringValue == "gc")
        #expect(window.renderSnapshot(screenFrame: screen, scale: 1, backdrop: nil) != nil)

        window.update(model(overlay: .output(title: "Disk Usage", text: "42 GB free", isError: false), focus: .none))
        #expect(content.list.isHidden)
        #expect(!content.output.isHidden)
        #expect(content.output.text == "42 GB free")
        #expect(window.renderSnapshot(screenFrame: screen, scale: 1, backdrop: nil) != nil)

        window.update(model(overlay: .confirmation(
            title: "Shut Down", message: "Are you sure you want to shut down?", confirmTitle: "Shut Down"
        ), focus: .none))
        #expect(content.output.isHidden)
        #expect(!content.list.isHidden)
        #expect(!content.confirmation.isHidden)
        #expect(content.confirmation.confirmButtonTitle == "Shut Down ↵")
        let image = try #require(window.renderSnapshot(screenFrame: screen, scale: 2, backdrop: nil))
        #expect(image.width == 3024)
    }

    @Test("an empty model shows the empty text instead of rows")
    func emptyModelRenders() throws {
        let window = LauncherWindow()
        window.present(model(sections: [], selectedIndex: nil, emptyText: "No results"), screenFrame: screen)

        #expect(window.rowViews.isEmpty)
        #expect(window.content.list.isShowingEmptyText)
        let image = try #require(window.renderSnapshot(screenFrame: screen, scale: 2, backdrop: nil))
        #expect(image.height == 1898)
    }

    @Test("the model's focus decides which field is the first responder")
    func focusFollowsModel() {
        let window = LauncherWindow()
        let arguments = [
            ArgumentFieldViewModel(placeholder: "query", value: "", isSecure: false, options: nil, isOptional: false),
            ArgumentFieldViewModel(placeholder: "token", value: "", isSecure: true, options: nil, isOptional: true),
        ]
        window.present(model(arguments: arguments, focus: .argument(0)), screenFrame: screen)

        #expect(window.argumentControls.count == 2)
        #expect(window.focusedView === window.argumentControls[0])

        window.update(model(arguments: arguments, focus: .argument(1)))
        #expect(window.argumentControls[1] is NSSecureTextField)
        #expect(window.focusedView === window.argumentControls[1])

        window.update(model(arguments: arguments, focus: .query))
        #expect(window.focusedView === window.content.searchBar.queryField)
    }

    @Test("model text updates replace the field text without reporting an edit")
    func modelUpdatesDoNotEcho() {
        let window = LauncherWindow()
        var reported: [String] = []
        window.onQueryChange = { reported.append($0) }
        window.present(model(query: "chr"), screenFrame: screen)

        window.update(model(query: "chrome"))

        #expect(window.content.searchBar.queryField.stringValue == "chrome")
        #expect(reported.isEmpty)
    }

    @Test("picking a dropdown option reports its title for that argument")
    func dropdownReportsTitle() throws {
        let window = LauncherWindow()
        var reported: [(Int, String)] = []
        window.onArgumentChange = { reported.append(($0, $1)) }
        let arguments = [
            ArgumentFieldViewModel(placeholder: "query", value: "", isSecure: false, options: nil, isOptional: false),
            ArgumentFieldViewModel(placeholder: "engine", value: "", isSecure: false, options: ["Google", "Kagi"], isOptional: false),
        ]
        window.present(model(arguments: arguments), screenFrame: screen)
        let popUp = try #require(window.argumentControls[1] as? NSPopUpButton)
        #expect(popUp.titleOfSelectedItem == "engine")

        popUp.selectItem(at: 2)
        let action = try #require(popUp.action)
        NSApp.sendAction(action, to: popUp.target, from: popUp)

        #expect(reported.count == 1)
        #expect(reported.first?.0 == 1)
        #expect(reported.first?.1 == "Kagi")
    }

    @Test("a HUD renders on its own after the launcher is dismissed")
    func hudRendersWithoutPanel() {
        let window = LauncherWindow()
        window.present(model(), screenFrame: screen)
        window.dismiss()

        window.showHUD("Copied", screenFrame: screen)

        #expect(window.isHUDShowing)
        #expect(window.hud.frame.minY == (screen.minY + screen.height / 6).rounded())
        #expect(window.renderSnapshot(screenFrame: screen, scale: 1, backdrop: nil) != nil)
    }

    @Test("dismissing hides the panel, and dismissing again is harmless")
    func dismissHides() {
        let window = LauncherWindow()
        var resigned = 0
        window.onResignKey = { resigned += 1 }
        window.present(model(), screenFrame: screen)

        window.dismiss()
        window.dismiss()

        #expect(!window.isPresented)
        #expect(resigned == 0)
    }

    // MARK: - Fixtures

    private func row(_ key: String, _ title: String, hotkey: [String] = [], alias: String? = nil) -> RowViewModel {
        RowViewModel(
            id: ItemID(rawValue: "app:\(key)"),
            title: title,
            titleHighlights: [NSRange(location: 0, length: 2)],
            subtitle: "/Applications",
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            accessory: "Application",
            alias: alias,
            hotkeyKeys: hotkey
        )
    }

    private func twoSections() -> [SectionViewModel] {
        [
            SectionViewModel(title: "favorites", rows: [
                row("com.google.Chrome", "Google Chrome", hotkey: ["⌘", "1"], alias: "gc"),
            ]),
            SectionViewModel(title: "results", rows: [
                row("com.apple.Safari", "Safari"),
                row("com.tinyspeck.slackmacgap", "Slack", hotkey: ["⌥", "S"]),
            ]),
        ]
    }

    private func model(
        query: String = "",
        arguments: [ArgumentFieldViewModel] = [],
        sections: [SectionViewModel]? = nil,
        selectedIndex: Int? = 0,
        overlay: OverlayViewModel = .none,
        focus: LauncherFocus = .query,
        emptyText: String? = nil
    ) -> LauncherViewModel {
        LauncherViewModel(
            theme: .missionControl,
            query: query,
            placeholder: "Search for apps and commands…",
            arguments: arguments,
            sections: sections ?? twoSections(),
            selectedIndex: selectedIndex,
            footer: FooterViewModel(toast: nil, toastIsError: false, primaryTitle: "Open Application", showsActions: true),
            overlay: overlay,
            focus: focus,
            emptyText: emptyText
        )
    }
}
