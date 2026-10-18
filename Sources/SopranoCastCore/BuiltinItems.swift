import Foundation

/// The items Soprano Cast ships with (system, window and its own commands) plus one item
/// per quicklink in settings.
public enum BuiltinItems {
    /// Every SystemCommand, WindowCommand and CastCommand item plus one item per quicklink,
    /// with titles, subtitles ("System", "Window Management", the quicklink's link),
    /// keywords (e.g. "fullscreen", "dark mode", "trash", "half"), icons (`.glyph`, quicklink
    /// emoji/path), `needsConfirmation`, and arguments (search commands: one "Query";
    /// quicklinks: `QuicklinkTemplate.arguments`).
    public static func items(settings: CastSettings) -> [CastItem] {
        SystemCommand.allCases.map(item(for:))
            + WindowCommand.allCases.map(item(for:))
            + CastCommand.allCases.map(item(for:))
            + settings.quicklinks.map(item(for:))
    }

    static func item(for command: SystemCommand) -> CastItem {
        CastItem(
            id: ItemID(kind: .systemCommand, key: command.rawValue),
            title: command.title,
            subtitle: "System",
            keywords: keywords(for: command),
            icon: .glyph(command.glyph),
            needsConfirmation: command.needsConfirmation
        )
    }

    static func item(for command: WindowCommand) -> CastItem {
        CastItem(
            id: ItemID(kind: .windowCommand, key: command.rawValue),
            title: command.title,
            subtitle: "Window Management",
            keywords: ["window"] + keywords(for: command),
            icon: .glyph(.window)
        )
    }

    static func item(for command: CastCommand) -> CastItem {
        CastItem(
            id: ItemID(kind: .castCommand, key: command.rawValue),
            title: command.title,
            subtitle: "Soprano Cast",
            keywords: keywords(for: command),
            icon: .glyph(command.glyph),
            arguments: arguments(for: command)
        )
    }

    static func item(for quicklink: Quicklink) -> CastItem {
        CastItem(
            id: ItemID(kind: .quicklink, key: quicklink.id),
            title: quicklink.name,
            subtitle: quicklink.link,
            icon: icon(for: quicklink),
            arguments: QuicklinkTemplate.arguments(in: quicklink.link)
        )
    }

    /// An emoji → `.emoji`; something path-like ("/…" or "~…") → `.file`; anything else,
    /// or no icon → the link glyph.
    static func icon(for quicklink: Quicklink) -> ItemIcon {
        guard let text = quicklink.icon?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return .glyph(.link)
        }
        if IconText.isEmoji(text) { return .emoji(text) }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return .file(path: (text as NSString).expandingTildeInPath)
        }
        return .glyph(.link)
    }

    private static func arguments(for command: CastCommand) -> [ArgumentSpec] {
        switch command {
        case .searchGoogle, .searchDuckDuckGo: [ArgumentSpec(name: "Query", placeholder: "Query")]
        case .openSettings, .reloadScripts, .quit: []
        }
    }

    private static func keywords(for command: SystemCommand) -> [String] {
        switch command {
        case .lockScreen: ["lock", "screen", "security", "away"]
        case .sleep: ["sleep", "suspend", "standby"]
        case .sleepDisplays: ["sleep", "display", "monitor", "screen", "off"]
        case .restart: ["restart", "reboot", "power"]
        case .shutDown: ["shutdown", "shut down", "power off", "turn off"]
        case .logOut: ["log out", "logout", "sign out", "log off"]
        case .emptyTrash: ["trash", "bin", "delete", "empty"]
        case .ejectAllDisks: ["eject", "disk", "drive", "volume", "unmount"]
        case .toggleSystemAppearance: ["dark mode", "light mode", "appearance", "theme"]
        case .quitAllApplications: ["quit", "close", "apps", "kill"]
        case .hideOtherApplications: ["hide", "others", "apps", "focus"]
        case .toggleHiddenFiles: ["hidden", "files", "dotfiles", "finder", "show"]
        }
    }

    private static func keywords(for command: WindowCommand) -> [String] {
        let split = ["split", "tile", "snap"]
        switch command {
        case .toggleFullscreen: return ["fullscreen", "full screen"]
        case .maximize: return ["fill", "full", "zoom", "fullscreen"]
        case .almostMaximize: return ["almost", "maximize", "large"]
        case .maximizeHeight: return ["height", "vertical", "tall"]
        case .maximizeWidth: return ["width", "horizontal", "wide"]
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return ["half"] + split
        case .centerHalf: return ["half", "center", "middle"]
        case .center: return ["middle", "centre"]
        case .moveUp, .moveDown, .moveLeft, .moveRight: return ["move", "edge", "snap"]
        case .restore: return ["undo", "previous", "reset", "original"]
        case .reasonableSize: return ["resize", "medium", "default size"]
        case .makeLarger: return ["bigger", "grow", "increase", "resize"]
        case .makeSmaller: return ["shrink", "decrease", "resize"]
        case .firstThird, .centerThird, .lastThird: return ["third"] + split
        case .firstTwoThirds, .lastTwoThirds: return ["two thirds", "third"] + split
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth: return ["fourth", "quarter"] + split
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return ["quarter", "corner"] + split
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            return ["sixth", "grid"] + split
        case .previousDisplay, .nextDisplay: return ["display", "monitor", "screen", "move"]
        }
    }

    private static func keywords(for command: CastCommand) -> [String] {
        switch command {
        case .openSettings: ["settings", "preferences", "config", "configure"]
        case .reloadScripts: ["scripts", "reload", "refresh"]
        case .searchGoogle: ["google", "web", "search"]
        case .searchDuckDuckGo: ["duckduckgo", "ddg", "web", "search"]
        case .quit: ["quit", "exit"]
        }
    }
}

/// Classifies icon text from settings and script metadata.
enum IconText {
    /// Exactly one emoji grapheme (a flag, a ZWJ sequence or a keycap counts as one).
    static func isEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Text-default emoji (☀, ❤, 1️⃣) need a variation selector or a combining sequence.
        return first.properties.isEmoji && scalars.count > 1
    }
}
