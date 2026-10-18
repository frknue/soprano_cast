import Foundation

// settings.json spellings, display symbols and event matching for the types in Keys.swift.

extension ModifierKey {
    /// ⌃⌥⇧⌘fn — the order modifiers are spelled and shown in.
    public static let canonicalOrder: [ModifierKey] = [.control, .option, .shift, .command, .function]

    /// The canonical settings.json spelling: "ctrl", "opt", "shift", "cmd", "fn".
    public var settingsName: String {
        switch self {
        case .control: "ctrl"
        case .option: "opt"
        case .shift: "shift"
        case .command: "cmd"
        case .function: "fn"
        }
    }

    /// Every accepted spelling (lowercase), the canonical one included.
    public var aliases: Set<String> {
        switch self {
        case .control: ["ctrl", "control", "⌃"]
        case .option: ["opt", "option", "alt", "⌥"]
        case .shift: ["shift", "⇧"]
        case .command: ["cmd", "command", "⌘"]
        case .function: ["fn", "function"]
        }
    }

    /// "⌃", "⌥", "⇧", "⌘", "fn".
    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        case .function: "fn"
        }
    }

    public var member: ModifierSet {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        case .function: .function
        }
    }

    /// The physical key on `side`; nil for fn (one key, no sides) and for `.any`.
    public func physicalKey(on side: KeySide) -> ModifierSides? {
        switch (self, side) {
        case (.control, .left): .leftControl
        case (.control, .right): .rightControl
        case (.option, .left): .leftOption
        case (.option, .right): .rightOption
        case (.shift, .left): .leftShift
        case (.shift, .right): .rightShift
        case (.command, .left): .leftCommand
        case (.command, .right): .rightCommand
        default: nil
        }
    }

    /// Every physical key of this modifier (fn: `.function`).
    public var physicalKeys: ModifierSides {
        switch self {
        case .control: [.leftControl, .rightControl]
        case .option: [.leftOption, .rightOption]
        case .shift: [.leftShift, .rightShift]
        case .command: [.leftCommand, .rightCommand]
        case .function: .function
        }
    }

    /// Any accepted spelling, case-insensitive; nil for anything else.
    public init?(settingsName: String) {
        let lowered = settingsName.lowercased()
        guard let key = Self.canonicalOrder.first(where: { $0.aliases.contains(lowered) }) else { return nil }
        self = key
    }
}

extension ModifierSet {
    /// "cmd"/"command"/"⌘", "opt"/"option"/"alt"/"⌥", "ctrl"/"control"/"⌃", "shift"/"⇧",
    /// "fn"/"function", joined with "+", case-insensitive, spaces ignored; nil when empty/unknown.
    public init?(settingsText: String) {
        let compact = settingsText.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        var result: ModifierSet = []
        for part in compact.split(separator: "+", omittingEmptySubsequences: false) {
            guard let key = ModifierKey(settingsName: String(part)) else { return nil }
            result.insert(key.member)
        }
        self = result
    }

    /// The modifier keys present, in canonical order.
    public var keys: [ModifierKey] {
        ModifierKey.canonicalOrder.filter { contains($0.member) }
    }

    /// Canonical spelling: "ctrl+opt+shift+cmd+fn" order, only the members present.
    public var settingsText: String {
        keys.map(\.settingsName).joined(separator: "+")
    }

    /// ["⌃","⌥","⇧","⌘","fn"] order, only the members present.
    public var symbols: [String] {
        keys.map(\.symbol)
    }
}

extension KeySpec {
    /// Alternative spellings of named keys (lowercase).
    private static let aliases: [String: NamedKey] = [
        "enter": .return,
        "esc": .escape,
        "backspace": .delete,
        "spacebar": .space,
    ]

    /// A NamedKey raw value (case-insensitive) or alias (enter→return, esc→escape,
    /// backspace→delete, spacebar→space), or one non-space character → .character(lowercased).
    public init?(settingsText: String) {
        let trimmed = settingsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if let named = NamedKey.allCases.first(where: { $0.rawValue.lowercased() == lowered }) {
            self = .named(named)
        } else if let named = Self.aliases[lowered] {
            self = .named(named)
        } else if trimmed.count == 1, let character = trimmed.first {
            // Lowercasing can change a character's length; keep it as typed then.
            let lowercased = String(character).lowercased()
            self = .character(lowercased.count == 1 ? Character(lowercased) : character)
        } else {
            return nil
        }
    }

    /// Round-trips through `init(settingsText:)`.
    public var settingsText: String {
        switch self {
        case .named(let key): key.rawValue
        case .character(let character): String(character)
        }
    }

    /// ⇥ ␣ ↩ ⎋ ⌫ ⌦ ← → ↑ ↓ ↖ ↘ ⇞ ⇟ F1…F20; characters uppercased ("K").
    public var symbol: String {
        switch self {
        case .character(let character):
            return String(character).uppercased()
        case .named(let key):
            switch key {
            case .tab: return "⇥"
            case .space: return "␣"
            case .return: return "↩"
            case .escape: return "⎋"
            case .delete: return "⌫"
            case .forwardDelete: return "⌦"
            case .left: return "←"
            case .right: return "→"
            case .up: return "↑"
            case .down: return "↓"
            case .home: return "↖"
            case .end: return "↘"
            case .pageUp: return "⇞"
            case .pageDown: return "⇟"
            case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
                 .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
                return key.rawValue.uppercased()
            }
        }
    }

    /// Named: `keyCodes` contains `event.keyCode`. Character: `event.baseCharacters`
    /// lowercased equals the character (so ⇧⌘1 matches "1", not "!"); false when nil.
    /// Modifiers are not compared.
    public func matches(_ event: KeyEvent) -> Bool {
        switch self {
        case .named(let key):
            return key.keyCodes.contains(event.keyCode)
        case .character(let character):
            guard let base = event.baseCharacters else { return false }
            return base.lowercased() == String(character)
        }
    }
}
