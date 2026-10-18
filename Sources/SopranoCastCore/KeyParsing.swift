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

/// US-ANSI names of the printable keys, by virtual key code (Carbon `kVK_ANSI_*`), for
/// `KeySpec.physical`: a–z, 0–9, - = [ ] \ ; ' , . / ` and § (0x0A, the ISO key above Tab).
public enum PhysicalKeyNames {
    private static let names: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
        0x08: "c", 0x09: "v", 0x0A: "§", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r",
        0x10: "y", 0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "o",
        0x20: "u", 0x21: "[", 0x22: "i", 0x23: "p", 0x25: "l", 0x26: "j", 0x27: "'", 0x28: "k",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".", 0x32: "`",
    ]

    private static let codes: [String: UInt16] = Dictionary(uniqueKeysWithValues: names.map { ($0.value, $0.key) })

    /// The US-ANSI name of the key at `code` ("a", "'", "§"); nil for keys without one.
    public static func name(forKeyCode code: UInt16) -> String? {
        names[code]
    }

    /// The key code of a US-ANSI key name, case-insensitive; nil for unknown names.
    public static func keyCode(forName name: String) -> UInt16? {
        codes[name.lowercased()]
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

    /// The prefix of physical keys in settings.json ("key:'", "key:0x27").
    private static let physicalPrefix = "key:"

    /// A NamedKey raw value (case-insensitive) or alias (enter→return, esc→escape,
    /// backspace→delete, spacebar→space); `key:<US name>` (case-insensitive) or `key:0x<hex>`
    /// (0…127, not a NamedKey code) → `.physical`; or one non-space character →
    /// `.character(lowercased)`.
    public init?(settingsText: String) {
        let trimmed = settingsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix(Self.physicalPrefix) {
            guard let code = Self.physicalKeyCode(String(lowered.dropFirst(Self.physicalPrefix.count))) else {
                return nil
            }
            self = .physical(code)
        } else if let named = NamedKey.allCases.first(where: { $0.rawValue.lowercased() == lowered }) {
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

    /// A US key name or "0x<hex>" (0…127, not a NamedKey code).
    private static func physicalKeyCode(_ text: String) -> UInt16? {
        if let code = PhysicalKeyNames.keyCode(forName: text) { return code }
        guard text.hasPrefix("0x"), let code = UInt16(text.dropFirst(2), radix: 16), code <= 127,
              !NamedKey.allCases.contains(where: { $0.keyCodes.contains(code) })
        else { return nil }
        return code
    }

    /// "0x27": a key code without a US name.
    private static func hexName(_ code: UInt16) -> String {
        "0x" + (code < 0x10 ? "0" : "") + String(code, radix: 16)
    }

    /// Round-trips through `init(settingsText:)`; physical keys `key:<name>`, or `key:0x<hex>`
    /// without a name.
    public var settingsText: String {
        switch self {
        case .named(let key): key.rawValue
        case .physical(let code): Self.physicalPrefix + (PhysicalKeyNames.name(forKeyCode: code) ?? Self.hexName(code))
        case .character(let character): String(character)
        }
    }

    /// ⇥ ␣ ↩ ⎋ ⌫ ⌦ ← → ↑ ↓ ↖ ↘ ⇞ ⇟ F1…F20; characters and physical key names uppercased
    /// ("K", "'", "§"); unnamed physical keys "0x4b".
    public var symbol: String {
        switch self {
        case .character(let character):
            return String(character).uppercased()
        case .physical(let code):
            return PhysicalKeyNames.name(forKeyCode: code)?.uppercased() ?? Self.hexName(code)
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

    /// Named: `keyCodes` contains `event.keyCode`. Physical: `event.keyCode` equals the code.
    /// Character: `event.baseCharacters` lowercased equals the character (so ⇧⌘1 matches "1",
    /// not "!"); false when nil. Modifiers are not compared.
    public func matches(_ event: KeyEvent) -> Bool {
        switch self {
        case .named(let key):
            return key.keyCodes.contains(event.keyCode)
        case .physical(let code):
            return event.keyCode == code
        case .character(let character):
            guard let base = event.baseCharacters else { return false }
            return base.lowercased() == String(character)
        }
    }
}
