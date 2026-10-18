import AppKit
import SopranoCastCore

/// Converts CGEvents (global event taps) and NSEvents (the launcher panel's local monitor)
/// into Core `KeyEvent`s. Call on the main thread: NSEvent reads the keyboard layout there.
enum KeyEventConversion {
    /// The `KeyEvent` for a keyDown, keyUp or flagsChanged event; nil for any other type.
    /// `characters` is `charactersIgnoringModifiers` (Shift still applies) and
    /// `baseCharacters` what the key types with no modifiers at all; both nil for
    /// flagsChanged. `timestamp` is the event's nanosecond timestamp in seconds.
    static func keyEvent(from event: CGEvent, type: CGEventType) -> KeyEvent? {
        let kind: KeyEvent.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return nil
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        var characters: String?
        var baseCharacters: String?
        if kind != .flagsChanged, let nsEvent = NSEvent(cgEvent: event) {
            characters = nsEvent.charactersIgnoringModifiers
            baseCharacters = nsEvent.characters(byApplyingModifiers: [])
        }
        return makeEvent(
            kind: kind,
            keyCode: keyCode,
            modifiers: modifiers(from: event.flags),
            sides: sides(from: event.flags),
            characters: characters,
            baseCharacters: baseCharacters,
            isRepeat: kind != .flagsChanged && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            timestamp: TimeInterval(event.timestamp) / 1_000_000_000
        )
    }

    /// The `KeyEvent` for an NSEvent keyDown, keyUp or flagsChanged; nil for any other type.
    /// Sides come from the device-dependent bits in `modifierFlags.rawValue`, which carry
    /// the same NX_DEVICE… values as CGEventFlags.
    static func keyEvent(from event: NSEvent) -> KeyEvent? {
        let kind: KeyEvent.Kind
        switch event.type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return nil
        }
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let isKey = kind != .flagsChanged
        return makeEvent(
            kind: kind,
            keyCode: event.keyCode,
            modifiers: modifiers(from: flags),
            sides: sides(from: flags),
            characters: isKey ? event.charactersIgnoringModifiers : nil,
            baseCharacters: isKey ? event.characters(byApplyingModifiers: []) : nil,
            isRepeat: isKey && event.isARepeat,
            timestamp: event.timestamp
        )
    }

    /// The side-agnostic modifiers in `flags`, `.function` from `maskSecondaryFn`.
    static func modifiers(from flags: CGEventFlags) -> ModifierSet {
        var modifiers: ModifierSet = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        return modifiers
    }

    /// The physical modifier keys in `flags`, from the device-dependent NX_DEVICE… bits;
    /// fn (which has one key) from `maskSecondaryFn`.
    static func sides(from flags: CGEventFlags) -> ModifierSides {
        let raw = flags.rawValue
        var sides: ModifierSides = []
        for (mask, side) in deviceSideMasks where raw & mask != 0 {
            sides.insert(side)
        }
        if flags.contains(.maskSecondaryFn) { sides.insert(.function) }
        return sides
    }

    /// NX_DEVICE…KEYMASK bits (IOKit's IOLLEvent.h).
    private static let deviceSideMasks: [(UInt64, ModifierSides)] = [
        (0x0000_0008, .leftCommand),   // NX_DEVICELCMDKEYMASK
        (0x0000_0010, .rightCommand),  // NX_DEVICERCMDKEYMASK
        (0x0000_0020, .leftOption),    // NX_DEVICELALTKEYMASK
        (0x0000_0040, .rightOption),   // NX_DEVICERALTKEYMASK
        (0x0000_0001, .leftControl),   // NX_DEVICELCTLKEYMASK
        (0x0000_2000, .rightControl),  // NX_DEVICERCTLKEYMASK
        (0x0000_0002, .leftShift),     // NX_DEVICELSHIFTKEYMASK
        (0x0000_0004, .rightShift),    // NX_DEVICERSHIFTKEYMASK
    ]

    /// Keys macOS always flags with fn (`maskSecondaryFn` / `NSEvent.ModifierFlags.function`)
    /// whether or not fn is held: arrows, Home/End, Page Up/Down, Forward Delete, Help and
    /// F1–F20. Their key events drop `.function`, so ⌃⌥← is ⌃⌥←, not fn⌃⌥←, everywhere
    /// (recorder, launcher router, hotkey matching). On Apple keyboards fn plus one of these
    /// produces a different key code anyway (fn← is Home).
    static let inherentFunctionKeyCodes: Set<UInt16> = {
        let named: [NamedKey] = [
            .left, .right, .up, .down, .home, .end, .pageUp, .pageDown, .forwardDelete,
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
        ]
        return Set(named.flatMap { $0.keyCodes }).union([0x72]) // kVK_Help
    }()

    private static func makeEvent(
        kind: KeyEvent.Kind,
        keyCode: UInt16,
        modifiers: ModifierSet,
        sides: ModifierSides,
        characters: String?,
        baseCharacters: String?,
        isRepeat: Bool,
        timestamp: TimeInterval
    ) -> KeyEvent {
        var modifiers = modifiers
        var sides = sides
        if kind != .flagsChanged, inherentFunctionKeyCodes.contains(keyCode) {
            modifiers.remove(.function)
            sides.remove(.function)
        }
        return KeyEvent(
            kind: kind,
            keyCode: keyCode,
            modifiers: modifiers,
            sides: sides,
            characters: characters,
            baseCharacters: baseCharacters,
            isRepeat: isRepeat,
            timestamp: timestamp
        )
    }
}
