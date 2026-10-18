import Foundation

// Keys and hotkeys. Parsing, display strings, matching, recording and gesture detection
// live in the files docs/ARCHITECTURE.md → Core APIs names.

/// Modifier keys, side-agnostic.
public struct ModifierSet: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let control = ModifierSet(rawValue: 1 << 2)
    public static let shift = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    /// ⌃⌥⇧⌘ — what the Hyper key holds when it includes Shift.
    public static let hyper: ModifierSet = [.control, .option, .shift, .command]
}

/// Which physical modifier keys are down (CGEvent device-dependent flag bits).
public struct ModifierSides: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let leftCommand = ModifierSides(rawValue: 1 << 0)
    public static let rightCommand = ModifierSides(rawValue: 1 << 1)
    public static let leftOption = ModifierSides(rawValue: 1 << 2)
    public static let rightOption = ModifierSides(rawValue: 1 << 3)
    public static let leftControl = ModifierSides(rawValue: 1 << 4)
    public static let rightControl = ModifierSides(rawValue: 1 << 5)
    public static let leftShift = ModifierSides(rawValue: 1 << 6)
    public static let rightShift = ModifierSides(rawValue: 1 << 7)
    public static let function = ModifierSides(rawValue: 1 << 8)
}

/// A key identified by its position (virtual key code), independent of the layout.
public enum NamedKey: String, CaseIterable, Hashable, Sendable {
    case tab
    case space
    case `return`
    case escape
    case delete
    case forwardDelete
    case left
    case right
    case up
    case down
    case home
    case end
    case pageUp
    case pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    /// macOS virtual key codes (Carbon `kVK_*`); the first is the canonical one.
    public var keyCodes: [UInt16] {
        switch self {
        case .tab: [0x30]
        case .space: [0x31]
        case .return: [0x24, 0x4C] // Return and keypad Enter
        case .escape: [0x35]
        case .delete: [0x33]
        case .forwardDelete: [0x75]
        case .left: [0x7B]
        case .right: [0x7C]
        case .down: [0x7D]
        case .up: [0x7E]
        case .home: [0x73]
        case .end: [0x77]
        case .pageUp: [0x74]
        case .pageDown: [0x79]
        case .f1: [0x7A]
        case .f2: [0x78]
        case .f3: [0x63]
        case .f4: [0x76]
        case .f5: [0x60]
        case .f6: [0x61]
        case .f7: [0x62]
        case .f8: [0x64]
        case .f9: [0x65]
        case .f10: [0x6D]
        case .f11: [0x67]
        case .f12: [0x6F]
        case .f13: [0x69]
        case .f14: [0x6B]
        case .f15: [0x71]
        case .f16: [0x6A]
        case .f17: [0x40]
        case .f18: [0x4F]
        case .f19: [0x50]
        case .f20: [0x5A]
        }
    }

    /// F13–F20: keys Raycast accepts as hotkeys without a modifier.
    public var canStandAlone: Bool {
        switch self {
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20: true
        default: false
        }
    }
}

/// One non-modifier key.
///
/// - `named`: a special key by position (arrows, Return, F-keys …).
/// - `physical`: a printable key by position, independent of the layout — Raycast's default
///   for recorded hotkeys, so ⌘' keeps working when the user switches from ABC to German
///   (where the same key types "ä"). Settings spelling: `key:<US name>` (`key:'`, `key:§`,
///   `key:z`) or `key:0x27`.
/// - `character`: a "key equivalent": the key that types this character (lowercased) on the
///   current layout, re-resolved when the layout changes. Settings spelling: the character.
public enum KeySpec: Hashable, Sendable {
    case named(NamedKey)
    case physical(UInt16)
    case character(Character)
}

/// One keyboard event (from the launcher panel's local monitor or a global event tap).
public struct KeyEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public var kind: Kind
    public var keyCode: UInt16
    /// Modifiers held after this event.
    public var modifiers: ModifierSet
    /// Physical modifier keys held after this event.
    public var sides: ModifierSides
    /// `charactersIgnoringModifiers` (Shift still applies); nil for flagsChanged.
    public var characters: String?
    /// What the key types with no modifiers at all on the current layout
    /// (`NSEvent.characters(byApplyingModifiers: [])`); nil for flagsChanged. Character
    /// hotkeys match this, so ⇧⌘1 matches "1", not "!".
    public var baseCharacters: String?
    public var isRepeat: Bool
    /// Seconds since an arbitrary epoch; used for tap and double-tap timing.
    public var timestamp: TimeInterval

    public init(
        kind: Kind,
        keyCode: UInt16,
        modifiers: ModifierSet,
        sides: ModifierSides = [],
        characters: String? = nil,
        baseCharacters: String? = nil,
        isRepeat: Bool = false,
        timestamp: TimeInterval = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.sides = sides
        self.characters = characters
        self.baseCharacters = baseCharacters
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }
}

/// A modifier key as a hotkey component.
public enum ModifierKey: String, CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
    case function
}

public enum KeySide: String, CaseIterable, Hashable, Sendable {
    case any
    case left
    case right
}

/// A modifier key, optionally pinned to one side ("rcmd" = right ⌘).
public struct SidedModifier: Hashable, Sendable {
    public var key: ModifierKey
    public var side: KeySide

    public init(_ key: ModifierKey, side: KeySide = .any) {
        self.key = key
        self.side = side
    }
}

/// Modifiers plus one key, pressed together.
public struct HotkeyCombo: Hashable, Sendable {
    public var modifiers: ModifierSet
    /// Written as `hyper` in settings: adds the Hyper key's modifiers (⌃⌥⇧⌘, or ⌃⌥⌘ when
    /// the Hyper key excludes Shift) at registration.
    public var usesHyper: Bool
    public var key: KeySpec

    public init(modifiers: ModifierSet, usesHyper: Bool = false, key: KeySpec) {
        self.modifiers = modifiers
        self.usesHyper = usesHyper
        self.key = key
    }

    /// The modifiers to register, with `hyper` expanded.
    public func effectiveModifiers(hyperIncludesShift: Bool) -> ModifierSet {
        guard usesHyper else { return modifiers }
        return modifiers.union(hyperIncludesShift ? .hyper : [.control, .option, .command])
    }
}

/// Every hotkey shape Raycast supports.
public enum HotkeySpec: Hashable, Sendable {
    /// "cmd+shift+k", "hyper+1", "ctrl+opt+left", "f13" (F13–F20 may stand alone).
    case combo(HotkeyCombo)
    /// Modifier keys alone, pressed and released with nothing else: "rcmd", "cmd+opt", "fn".
    case modifierTap(Set<SidedModifier>)
    /// One modifier tapped twice quickly: "double:cmd", "double:rshift".
    case doubleTap(SidedModifier)
    /// Left and right of one modifier held together: "both:cmd".
    case bothSides(ModifierKey)
}

/// What a global hotkey runs.
public enum HotkeyTarget: Hashable, Sendable {
    /// Show or hide the launcher.
    case launcher
    case item(ItemID)
}

public struct HotkeyBinding: Hashable, Sendable {
    public var spec: HotkeySpec
    public var target: HotkeyTarget

    public init(spec: HotkeySpec, target: HotkeyTarget) {
        self.spec = spec
        self.target = target
    }
}
