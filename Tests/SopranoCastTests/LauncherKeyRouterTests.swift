import AppKit
import Testing
@testable import SopranoCastCore

struct LauncherKeyRouterTests {
    // MARK: Events

    private func named(_ key: NamedKey, _ modifiers: ModifierSet = [], repeat isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: key.keyCodes[0], modifiers: modifiers, isRepeat: isRepeat)
    }

    private func char(_ character: String, _ modifiers: ModifierSet = [], repeat isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: 0, modifiers: modifiers,
                 characters: character, baseCharacters: character, isRepeat: isRepeat)
    }

    private func input(
        _ context: LauncherContext = .root(argumentFocused: false),
        navigation: NavigationBindings = .emacs,
        top: Bool = false,
        bottom: Bool = false,
        arguments: Bool = false
    ) -> RouterInput {
        RouterInput(context: context, navigation: navigation, selectionAtTop: top,
                    selectionAtBottom: bottom, selectionHasArguments: arguments)
    }

    private func root(_ event: KeyEvent, _ routerInput: RouterInput? = nil) -> LauncherCommand? {
        LauncherKeyRouter.command(for: event, input: routerInput ?? input())
    }

    private let allContexts: [LauncherContext] = [
        .root(argumentFocused: false), .root(argumentFocused: true), .actionPanel,
        .aliasEditor, .output, .confirmation,
    ]

    // MARK: Global

    @Test("⌘W closes the window and ⌘Esc pops to root in every context but the recorder")
    func globalKeys() {
        for context in allContexts {
            #expect(LauncherKeyRouter.command(for: char("w", [.command]), input: input(context)) == .closeWindow)
            #expect(LauncherKeyRouter.command(for: named(.escape, [.command]), input: input(context)) == .popToRoot)
        }
    }

    @Test("the hotkey recorder gets every event, including Esc, Return and ⌘W")
    func recorderGetsEverything() {
        let recorder = input(.hotkeyRecorder)
        let events = [
            named(.escape), named(.return), named(.delete), named(.up), named(.escape, [.command]),
            char("w", [.command]), char("k", [.command]), char("1", [.command, .shift]), named(.tab),
        ]
        for event in events {
            #expect(LauncherKeyRouter.command(for: event, input: recorder) == nil)
        }
    }

    @Test("key up and flags changed events never route")
    func nonKeyDown() {
        var up = named(.return)
        up.kind = .keyUp
        let flags = KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: [.command])
        #expect(root(up) == nil)
        #expect(root(flags) == nil)
    }

    // MARK: Root movement

    @Test("arrows move the selection, and step through history only at the top or bottom")
    func arrowsAndHistory() {
        #expect(root(named(.up)) == .moveUp)
        #expect(root(named(.down)) == .moveDown)
        #expect(root(named(.up), input(top: true)) == .historyPrevious)
        #expect(root(named(.down), input(top: true)) == .moveDown)
        #expect(root(named(.down), input(bottom: true)) == .historyNext)
        #expect(root(named(.up), input(bottom: true)) == .moveUp)
    }

    @Test("arrow keys ignore the function flag macOS sets on them")
    func arrowsIgnoreFunction() {
        #expect(root(named(.down, [.function])) == .moveDown)
        #expect(root(named(.up, [.command, .function])) == .sectionUp)
    }

    @Test("emacs bindings use ⌃P and ⌃N only")
    func emacsBindings() {
        let emacs = input(navigation: .emacs)
        #expect(root(char("p", [.control]), emacs) == .moveUp)
        #expect(root(char("n", [.control]), emacs) == .moveDown)
        #expect(root(char("k", [.control]), emacs) == nil)
        #expect(root(char("j", [.control]), emacs) == nil)
    }

    @Test("vim bindings use ⌃K and ⌃J only")
    func vimBindings() {
        let vim = input(navigation: .vim)
        #expect(root(char("k", [.control]), vim) == .moveUp)
        #expect(root(char("j", [.control]), vim) == .moveDown)
        #expect(root(char("p", [.control]), vim) == nil)
        #expect(root(char("n", [.control]), vim) == nil)
    }

    @Test("both bindings accept emacs and vim keys")
    func bothBindings() {
        let both = input(navigation: .both)
        #expect(root(char("p", [.control]), both) == .moveUp)
        #expect(root(char("n", [.control]), both) == .moveDown)
        #expect(root(char("k", [.control]), both) == .moveUp)
        #expect(root(char("j", [.control]), both) == .moveDown)
    }

    @Test("navigation bindings never step into history")
    func bindingsSkipHistory() {
        #expect(root(char("p", [.control]), input(top: true)) == .moveUp)
        #expect(root(char("n", [.control]), input(bottom: true)) == .moveDown)
    }

    @Test("⌥ arrows page, ⌘ arrows jump sections and ⇧⌘ arrows reorder favorites")
    func modifiedArrows() {
        #expect(root(named(.up, [.option])) == .pageUp)
        #expect(root(named(.down, [.option])) == .pageDown)
        #expect(root(named(.up, [.command])) == .sectionUp)
        #expect(root(named(.down, [.command])) == .sectionDown)
        #expect(root(named(.up, [.shift, .command])) == .moveFavoriteUp)
        #expect(root(named(.down, [.shift, .command])) == .moveFavoriteDown)
    }

    // MARK: Root actions

    @Test("Return variants run the primary, secondary and tertiary actions")
    func returnVariants() {
        #expect(root(named(.return)) == .runPrimary)
        #expect(root(named(.return, [.command])) == .runSecondary)
        #expect(root(named(.return, [.option])) == .runTertiary)
        #expect(root(named(.return, [.shift])) == nil)
    }

    @Test("keypad Enter runs like Return")
    func keypadEnter() {
        let enter = KeyEvent(kind: .keyDown, keyCode: 0x4C, modifiers: [])
        #expect(root(enter) == .runPrimary)
    }

    @Test("root command shortcuts")
    func rootShortcuts() {
        #expect(root(char("k", [.command])) == .toggleActionPanel)
        #expect(root(char(",", [.shift, .command])) == .configureCommand)
        #expect(root(char(",", [.command])) == .openSettings)
        #expect(root(char("f", [.command])) == .toggleFavorite)
        #expect(root(char("d", [.shift, .command])) == .disableCommand)
        #expect(root(named(.escape)) == .back)
    }

    @Test("item action shortcuts run their action in root search")
    func rootActionShortcuts() {
        #expect(root(char("o", [.command])) == .runAction(.open))
        #expect(root(char("o", [.shift, .command])) == .runAction(.showInFinder))
        #expect(root(char("e", [.command])) == .runAction(.editScript))
        if case .runAction = root(char("c", [.shift, .command])) {} else {
            Issue.record("⇧⌘C should run a copy action")
        }
        if case .runAction = root(char("c", [.option, .command])) {} else {
            Issue.record("⌥⌘C should run a copy action")
        }
    }

    @Test("modifiers match exactly, so extra modifiers fall through")
    func exactModifiers() {
        #expect(root(char("k", [.command, .option])) == nil)
        #expect(root(char("o", [.command, .control])) == nil)
        #expect(root(named(.return, [.command, .option])) == nil)
    }

    @Test("typing, editing and caret keys pass to the search field")
    func typingPasses() {
        #expect(root(char("a")) == nil)
        #expect(root(char("A", [.shift])) == nil)
        #expect(root(named(.space)) == nil)
        #expect(root(named(.delete)) == nil)
        #expect(root(named(.left)) == nil)
        #expect(root(named(.right)) == nil)
        #expect(root(char("f", [.control])) == nil)
        #expect(root(char("b", [.control])) == nil)
        #expect(root(char("a", [.command])) == nil)
        #expect(root(char("c", [.command])) == nil)
        #expect(root(char("v", [.command])) == nil)
    }

    @Test("Tab cycles arguments only when the selection has them or one is focused")
    func tabRules() {
        #expect(root(named(.tab)) == nil)
        #expect(root(named(.tab, [.shift])) == nil)
        #expect(root(named(.tab), input(arguments: true)) == .nextArgument)
        #expect(root(named(.tab, [.shift]), input(arguments: true)) == .previousArgument)
        let focused = input(.root(argumentFocused: true))
        #expect(root(named(.tab), focused) == .nextArgument)
        #expect(root(named(.tab, [.shift]), focused) == .previousArgument)
    }

    // MARK: Repeats

    @Test("held keys repeat movement only")
    func repeats() {
        #expect(root(named(.down, repeat: true)) == .moveDown)
        #expect(root(named(.up, [.option], repeat: true)) == .pageUp)
        #expect(root(named(.down, [.command], repeat: true)) == .sectionDown)
        #expect(root(char("n", [.control], repeat: true)) == .moveDown)
        #expect(root(named(.return, repeat: true)) == nil)
        #expect(root(named(.escape, repeat: true)) == nil)
        #expect(root(char("k", [.command], repeat: true)) == nil)
        #expect(root(char("w", [.command], repeat: true)) == nil)
        #expect(root(named(.up, repeat: true), input(top: true)) == nil)
        #expect(LauncherKeyRouter.command(for: named(.return, repeat: true), input: input(.confirmation)) == nil)
    }

    // MARK: Action panel

    @Test("the action panel moves with arrows and the configured bindings")
    func actionPanelMovement() {
        let panel = input(.actionPanel, navigation: .vim, top: true, bottom: true)
        #expect(LauncherKeyRouter.command(for: named(.up), input: panel) == .moveUp)
        #expect(LauncherKeyRouter.command(for: named(.down), input: panel) == .moveDown)
        #expect(LauncherKeyRouter.command(for: char("k", [.control]), input: panel) == .moveUp)
        #expect(LauncherKeyRouter.command(for: char("j", [.control]), input: panel) == .moveDown)
        #expect(LauncherKeyRouter.command(for: char("n", [.control]), input: panel) == nil)
        let emacsPanel = input(.actionPanel, navigation: .emacs)
        #expect(LauncherKeyRouter.command(for: char("p", [.control]), input: emacsPanel) == .moveUp)
        #expect(LauncherKeyRouter.command(for: char("n", [.control]), input: emacsPanel) == .moveDown)
    }

    @Test("the action panel runs, toggles and backs out")
    func actionPanelKeys() {
        let panel = input(.actionPanel)
        #expect(LauncherKeyRouter.command(for: named(.return), input: panel) == .runPrimary)
        #expect(LauncherKeyRouter.command(for: named(.return, [.command]), input: panel) == .runSecondary)
        #expect(LauncherKeyRouter.command(for: char("k", [.command]), input: panel) == .toggleActionPanel)
        #expect(LauncherKeyRouter.command(for: named(.escape), input: panel) == .back)
    }

    @Test("action shortcuts run their action from the action panel")
    func actionPanelShortcuts() {
        let panel = input(.actionPanel)
        #expect(LauncherKeyRouter.command(for: char("o", [.command]), input: panel) == .runAction(.open))
        #expect(LauncherKeyRouter.command(for: char("f", [.command]), input: panel) == .runAction(.toggleFavorite))
        #expect(LauncherKeyRouter.command(for: char("d", [.shift, .command]), input: panel) == .runAction(.disableCommand))
        #expect(LauncherKeyRouter.command(for: named(.up, [.shift, .command]), input: panel) == .runAction(.moveFavoriteUp))
    }

    @Test("typing in the action panel passes to its filter field")
    func actionPanelTyping() {
        let panel = input(.actionPanel)
        #expect(LauncherKeyRouter.command(for: char("q"), input: panel) == nil)
        #expect(LauncherKeyRouter.command(for: named(.delete), input: panel) == nil)
        #expect(LauncherKeyRouter.command(for: named(.tab), input: panel) == nil)
        #expect(LauncherKeyRouter.command(for: named(.return, [.option]), input: panel) == nil)
        #expect(LauncherKeyRouter.command(for: named(.up, [.command]), input: panel) == nil)
    }

    // MARK: Small overlays

    @Test("the alias editor and confirmation save or confirm with Return and back out with Esc")
    func editorAndConfirmation() {
        for context: LauncherContext in [.aliasEditor, .confirmation] {
            #expect(LauncherKeyRouter.command(for: named(.return), input: input(context)) == .runPrimary)
            #expect(LauncherKeyRouter.command(for: named(.escape), input: input(context)) == .back)
            #expect(LauncherKeyRouter.command(for: named(.down), input: input(context)) == nil)
            #expect(LauncherKeyRouter.command(for: char("x"), input: input(context)) == nil)
            #expect(LauncherKeyRouter.command(for: char("o", [.command]), input: input(context)) == nil)
        }
    }

    @Test("the output view backs out with Return or Esc and leaves the rest to the text view")
    func output() {
        let output = input(.output)
        #expect(LauncherKeyRouter.command(for: named(.return), input: output) == .back)
        #expect(LauncherKeyRouter.command(for: named(.escape), input: output) == .back)
        #expect(LauncherKeyRouter.command(for: char("c", [.command]), input: output) == nil)
        #expect(LauncherKeyRouter.command(for: char("a", [.command]), input: output) == nil)
        #expect(LauncherKeyRouter.command(for: named(.down), input: output) == nil)
    }
}
