import Foundation

/// What the key router needs to know besides the event.
public struct RouterInput: Equatable, Sendable {
    public var context: LauncherContext
    public var navigation: NavigationBindings
    /// The first row is selected, or the list is empty (↑ steps into search history).
    public var selectionAtTop: Bool
    /// The last row is selected, or the list is empty (↓ steps forward in search history).
    public var selectionAtBottom: Bool
    /// The selected item takes arguments (Tab moves into its argument fields).
    public var selectionHasArguments: Bool

    public init(
        context: LauncherContext,
        navigation: NavigationBindings,
        selectionAtTop: Bool,
        selectionAtBottom: Bool,
        selectionHasArguments: Bool
    ) {
        self.context = context
        self.navigation = navigation
        self.selectionAtTop = selectionAtTop
        self.selectionAtBottom = selectionAtBottom
        self.selectionHasArguments = selectionHasArguments
    }
}

/// Raycast's in-launcher key map (docs/ARCHITECTURE.md → Launcher).
public enum LauncherKeyRouter {
    /// The command for a keyDown, or nil to pass it to the focused text field (or to the
    /// recorder in `.hotkeyRecorder`, which gets every event). flagsChanged → nil.
    ///
    /// Modifiers must match exactly; arrow keys ignore `.function`, which macOS sets on them.
    /// Auto-repeated keyDowns only produce movement commands (holding ↓ scrolls; holding ↵
    /// never runs twice).
    public static func command(for event: KeyEvent, input: RouterInput) -> LauncherCommand? {
        guard event.kind == .keyDown, input.context != .hotkeyRecorder else { return nil }
        guard let command = unfilteredCommand(for: event, input: input) else { return nil }
        if event.isRepeat && !isMovement(command) { return nil }
        return command
    }

    private static func unfilteredCommand(for event: KeyEvent, input: RouterInput) -> LauncherCommand? {
        let key = Matcher(event: event)
        if key.is(.character("w"), [.command]) { return .closeWindow }
        if key.is(.named(.escape), [.command]) { return .popToRoot }

        switch input.context {
        case .hotkeyRecorder:
            return nil
        case let .root(argumentFocused):
            return rootCommand(key, input: input, argumentFocused: argumentFocused)
        case .actionPanel:
            return actionPanelCommand(key, navigation: input.navigation)
        case .aliasEditor, .confirmation:
            if key.is(.named(.return), []) { return .runPrimary }
            if key.is(.named(.escape), []) { return .back }
            return nil
        case .output:
            if key.is(.named(.return), []) || key.is(.named(.escape), []) { return .back }
            return nil
        }
    }

    private static func rootCommand(_ key: Matcher, input: RouterInput, argumentFocused: Bool) -> LauncherCommand? {
        if key.is(.named(.up), []) { return input.selectionAtTop ? .historyPrevious : .moveUp }
        if key.is(.named(.down), []) { return input.selectionAtBottom ? .historyNext : .moveDown }
        if let move = navigationBinding(key, input.navigation) { return move }
        if key.is(.named(.up), [.option]) { return .pageUp }
        if key.is(.named(.down), [.option]) { return .pageDown }
        if key.is(.named(.up), [.command]) { return .sectionUp }
        if key.is(.named(.down), [.command]) { return .sectionDown }
        if key.is(.named(.up), [.shift, .command]) { return .moveFavoriteUp }
        if key.is(.named(.down), [.shift, .command]) { return .moveFavoriteDown }
        if key.is(.named(.return), []) { return .runPrimary }
        if key.is(.named(.return), [.command]) { return .runSecondary }
        if key.is(.named(.return), [.option]) { return .runTertiary }
        if key.is(.character("k"), [.command]) { return .toggleActionPanel }
        if key.is(.character(","), [.shift, .command]) { return .configureCommand }
        if key.is(.character(","), [.command]) { return .openSettings }
        if key.is(.character("f"), [.command]) { return .toggleFavorite }
        if key.is(.character("d"), [.shift, .command]) { return .disableCommand }
        if let action = actionShortcut(key) { return .runAction(action) }
        if input.selectionHasArguments || argumentFocused {
            if key.is(.named(.tab), []) { return .nextArgument }
            if key.is(.named(.tab), [.shift]) { return .previousArgument }
        }
        if key.is(.named(.escape), []) { return .back }
        return nil
    }

    private static func actionPanelCommand(_ key: Matcher, navigation: NavigationBindings) -> LauncherCommand? {
        if key.is(.named(.up), []) { return .moveUp }
        if key.is(.named(.down), []) { return .moveDown }
        if let move = navigationBinding(key, navigation) { return move }
        if key.is(.named(.return), []) { return .runPrimary }
        if key.is(.named(.return), [.command]) { return .runSecondary }
        if key.is(.character("k"), [.command]) { return .toggleActionPanel }
        if key.is(.named(.escape), []) { return .back }
        if let action = actionShortcut(key) { return .runAction(action) }
        return nil
    }

    /// ⌃P/⌃N (emacs) and ⌃K/⌃J (vim) as ↑/↓.
    private static func navigationBinding(_ key: Matcher, _ navigation: NavigationBindings) -> LauncherCommand? {
        if navigation != .vim {
            if key.is(.character("p"), [.control]) { return .moveUp }
            if key.is(.character("n"), [.control]) { return .moveDown }
        }
        if navigation != .emacs {
            if key.is(.character("k"), [.control]) { return .moveUp }
            if key.is(.character("j"), [.control]) { return .moveDown }
        }
        return nil
    }

    /// The first action (in declaration order) whose in-launcher shortcut is this key.
    /// Actions sharing a shortcut (⇧⌘C copies the path, link or result) never apply to the
    /// same item, so the launcher resolves `runAction` against the selection's actions.
    private static func actionShortcut(_ key: Matcher) -> ItemActionID? {
        ItemActionID.allCases.first { action in
            guard let combo = ItemActions.shortcut(for: action) else { return false }
            return key.is(combo.key, combo.modifiers)
        }
    }

    private static func isMovement(_ command: LauncherCommand) -> Bool {
        switch command {
        case .moveUp, .moveDown, .pageUp, .pageDown, .sectionUp, .sectionDown: true
        default: false
        }
    }

    private struct Matcher {
        let event: KeyEvent

        func `is`(_ key: KeySpec, _ modifiers: ModifierSet) -> Bool {
            guard key.matches(event) else { return false }
            var held = event.modifiers
            if case let .named(named) = key, Self.arrows.contains(named) {
                held.remove(.function)
            }
            return held == modifiers
        }

        private static let arrows: Set<NamedKey> = [.up, .down, .left, .right]
    }
}
