import Foundation

/// What the Action Panel (⌘K), ↵ / ⌘↵ / ⌥↵ and the in-launcher shortcuts do for an item.
public enum ItemActions {
    /// The Action Panel for an item, in this order (only those that apply):
    /// primary, secondary, showInFinder, copyPath/copyLink/copyResult, copyBundleID/copyName,
    /// quitApplication + hideApplication (running apps), editScript (scripts), toggleFavorite,
    /// moveFavoriteUp/Down (favorites not already first/last), setHotkey, deleteHotkey
    /// (when set), setAlias, deleteAlias (when set), disableCommand.
    ///
    /// The primary and secondary rows show ↵ and ⌘↵; an action already listed as one of them
    /// isn't repeated. The calculator row gets no favorite, hotkey, alias or disable actions
    /// (it is never stored in settings).
    public static func actions(for item: CastItem, isRunning: Bool, isFavorite: Bool,
                               canMoveFavoriteUp: Bool, canMoveFavoriteDown: Bool,
                               hasHotkey: Bool, hasAlias: Bool) -> [ItemAction] {
        var actions = [primary(for: item)]
        if let secondary = secondary(for: item) { actions.append(secondary) }
        func add(_ id: ItemActionID) {
            guard !actions.contains(where: { $0.id == id }) else { return }
            actions.append(action(id))
        }

        let kind = item.kind
        let isApp = kind == .application
        let hasFile = isApp || kind == .script
        if hasFile { add(.showInFinder) }
        switch kind {
        case .application, .script: add(.copyPath)
        case .quicklink: add(.copyLink)
        case .calculator: add(.copyResult)
        case .systemCommand, .windowCommand, .castCommand, nil: break
        }
        if kind != .calculator {
            add(isApp && hasBundleID(item) ? .copyBundleID : .copyName)
        }
        if isApp && isRunning {
            add(.quitApplication)
            add(.hideApplication)
        }
        if kind == .script { add(.editScript) }
        guard kind != .calculator else { return actions }

        actions.append(favoriteAction(isFavorite: isFavorite))
        if isFavorite && canMoveFavoriteUp { add(.moveFavoriteUp) }
        if isFavorite && canMoveFavoriteDown { add(.moveFavoriteDown) }
        actions += configureActions(hasHotkey: hasHotkey, hasAlias: hasAlias)
        add(.disableCommand)
        return actions
    }

    /// The Configure Command submenu: setHotkey, deleteHotkey (when set), setAlias, deleteAlias (when set).
    public static func configureActions(hasHotkey: Bool, hasAlias: Bool) -> [ItemAction] {
        var actions = [action(.setHotkey)]
        if hasHotkey { actions.append(action(.deleteHotkey)) }
        actions.append(action(.setAlias))
        if hasAlias { actions.append(action(.deleteAlias)) }
        return actions
    }

    /// ↵ / ⌘↵ / ⌥↵ for an item. Primary: open ("Open Application", "Open Quicklink", "Run
    /// Script", "Run Command", calculator "Copy Answer"). Secondary: app showInFinder,
    /// quicklink copyLink, script editScript, calculator copyResult, else nil. Tertiary:
    /// app copyPath, else nil. Their `shortcut` is ↵, ⌘↵ and ⌥↵.
    public static func primary(for item: CastItem) -> ItemAction {
        let title = switch item.kind {
        case .application: "Open Application"
        case .quicklink: "Open Quicklink"
        case .script: "Run Script"
        case .calculator: "Copy Answer"
        case .systemCommand, .windowCommand, .castCommand, nil: "Run Command"
        }
        return ItemAction(id: .open, title: title, shortcut: returnKey([]))
    }

    public static func secondary(for item: CastItem) -> ItemAction? {
        let id: ItemActionID? = switch item.kind {
        case .application: .showInFinder
        case .quicklink: .copyLink
        case .script: .editScript
        case .calculator: .copyResult
        case .systemCommand, .windowCommand, .castCommand, nil: nil
        }
        return id.map { action($0, shortcut: returnKey(.command)) }
    }

    public static func tertiary(for item: CastItem) -> ItemAction? {
        guard item.kind == .application else { return nil }
        return action(.copyPath, shortcut: returnKey(.option))
    }

    /// In-launcher shortcuts: open ⌘O, showInFinder ⇧⌘O, copyPath/copyLink/copyResult ⇧⌘C,
    /// copyBundleID/copyName ⌥⌘C, editScript ⌘E, toggleFavorite ⌘F, moveFavoriteUp ⇧⌘↑,
    /// moveFavoriteDown ⇧⌘↓, disableCommand ⇧⌘D. Others have none.
    public static func shortcut(for action: ItemActionID) -> HotkeyCombo? {
        switch action {
        case .open: combo(.command, "o")
        case .showInFinder: combo([.shift, .command], "o")
        case .copyPath, .copyLink, .copyResult: combo([.shift, .command], "c")
        case .copyBundleID, .copyName: combo([.option, .command], "c")
        case .editScript: combo(.command, "e")
        case .toggleFavorite: combo(.command, "f")
        case .moveFavoriteUp: HotkeyCombo(modifiers: [.shift, .command], key: .named(.up))
        case .moveFavoriteDown: HotkeyCombo(modifiers: [.shift, .command], key: .named(.down))
        case .disableCommand: combo([.shift, .command], "d")
        case .quitApplication, .hideApplication, .setHotkey, .deleteHotkey, .setAlias, .deleteAlias: nil
        }
    }

    private static func favoriteAction(isFavorite: Bool) -> ItemAction {
        ItemAction(
            id: .toggleFavorite,
            title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
            shortcut: shortcut(for: .toggleFavorite),
            isDestructive: isFavorite
        )
    }

    /// An action with its fixed title, its in-launcher shortcut (unless overridden) and
    /// whether it is destructive (quit, remove, disable).
    private static func action(_ id: ItemActionID, shortcut override: HotkeyCombo? = nil) -> ItemAction {
        let title = switch id {
        case .open: "Open"
        case .showInFinder: "Show in Finder"
        case .copyPath: "Copy Path"
        case .copyBundleID: "Copy Bundle Identifier"
        case .copyLink: "Copy Link"
        case .copyName: "Copy Name"
        case .copyResult: "Copy Answer"
        case .quitApplication: "Quit Application"
        case .hideApplication: "Hide Application"
        case .editScript: "Edit Script"
        case .toggleFavorite: "Add to Favorites"
        case .moveFavoriteUp: "Move Up in Favorites"
        case .moveFavoriteDown: "Move Down in Favorites"
        case .setHotkey: "Set Hotkey…"
        case .deleteHotkey: "Remove Hotkey"
        case .setAlias: "Set Alias…"
        case .deleteAlias: "Remove Alias"
        case .disableCommand: "Disable Command"
        }
        let isDestructive = switch id {
        case .quitApplication, .deleteHotkey, .deleteAlias, .disableCommand: true
        default: false
        }
        return ItemAction(id: id, title: title, shortcut: override ?? shortcut(for: id), isDestructive: isDestructive)
    }

    /// Apps without a bundle identifier are keyed by their absolute path.
    private static func hasBundleID(_ item: CastItem) -> Bool {
        !item.id.key.hasPrefix("/")
    }

    private static func combo(_ modifiers: ModifierSet, _ character: Character) -> HotkeyCombo {
        HotkeyCombo(modifiers: modifiers, key: .character(character))
    }

    private static func returnKey(_ modifiers: ModifierSet) -> HotkeyCombo {
        HotkeyCombo(modifiers: modifiers, key: .named(.return))
    }
}
