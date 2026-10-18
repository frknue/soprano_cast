import Foundation

/// Turns the key events the recorder overlay receives into a `HotkeySpec`, Raycast's way:
/// combos record on the key's keyDown, modifier-only shapes (taps, double taps, both sides)
/// when the last modifier is released.
///
/// - Escape / Return / Delete without modifiers → `.cancelled` / `.commit` / `.cleared`.
/// - Any other keyDown with a modifier, or F13–F20 alone, records a `.combo` (named key when
///   the key code is a `NamedKey`, else `.physical(keyCode)` — Raycast's default, so the
///   hotkey survives layout switches). ⌃⌥⇧⌘ records all four modifiers; the recorder never
///   writes "hyper".
/// - A keyDown of any other key without modifiers, a repeat, and a keyUp → `.unchanged`.
/// - flagsChanged while modifiers are held → `.pending(display:)` with sided keycaps ("R⌘").
///   Once a key went down during the hold, the recorded combo stays shown: further
///   flagsChanged until every modifier is up → `.unchanged`.
/// - Every modifier up, no key in between: one modifier → `.modifierTap([its side])`, several
///   → `.modifierTap(set)`, the same single modifier (same side) again with its press within
///   `doubleTapWindow` of the previous tap's release → `.doubleTap`, left and right of one
///   modifier (and nothing else) down at the same time → `.bothSides`. Any other combination
///   of both sides with more modifiers records nothing → `.pending(display: [])`.
public struct HotkeyRecorder: Sendable {
    public static let doubleTapWindow: TimeInterval = 0.35

    /// The last hotkey recorded; each `.recorded` replaces it.
    public private(set) var recorded: HotkeySpec?

    /// The modifier hold in progress (nil while every modifier is up).
    private var hold: ModifierHold?
    /// The last clean single-modifier tap, for double taps.
    private var lastTap: ModifierTapRecord?

    public init() {}

    public mutating func handle(_ event: KeyEvent) -> RecorderUpdate {
        switch event.kind {
        case .keyUp:
            return .unchanged
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            return handleFlagsChanged(event)
        }
    }

    private mutating func handleKeyDown(_ event: KeyEvent) -> RecorderUpdate {
        guard !event.isRepeat else { return .unchanged }
        hold?.keyWentDown = true
        lastTap = nil

        let named = NamedKey.allCases.first { $0.keyCodes.contains(event.keyCode) }
        if event.modifiers.isEmpty {
            switch named {
            case .escape?: return .cancelled
            case .return?: return .commit
            case .delete?: return .cleared
            case let key? where key.canStandAlone:
                return record(.combo(HotkeyCombo(modifiers: [], key: .named(key))))
            default: return .unchanged
            }
        }

        let key: KeySpec = named.map { .named($0) } ?? .physical(event.keyCode)
        return record(.combo(HotkeyCombo(modifiers: event.modifiers, key: key)))
    }

    private mutating func handleFlagsChanged(_ event: KeyEvent) -> RecorderUpdate {
        let held = HeldModifiers(event)
        if !held.isEmpty {
            if hold == nil { hold = ModifierHold(start: event.timestamp) }
            hold?.add(held)
            guard let hold, !hold.keyWentDown else { return .unchanged }
            return .pending(display: held.keycaps)
        }

        guard let finished = hold else { return .unchanged }
        hold = nil
        guard !finished.keyWentDown else { return .unchanged }
        guard let spec = gesture(of: finished, releasedAt: event.timestamp) else {
            lastTap = nil
            return .pending(display: [])
        }
        return record(spec)
    }

    /// The modifier-only hotkey a finished clean hold forms; updates `lastTap`.
    private mutating func gesture(of finished: ModifierHold, releasedAt: TimeInterval) -> HotkeySpec? {
        let keys = finished.pressed.keys
        if keys.count == 1, let key = keys.first, finished.bothDown.contains(key) {
            lastTap = nil
            return .bothSides(key)
        }
        guard finished.bothDown.isEmpty, !keys.isEmpty else { return nil }

        let modifiers = keys.map { SidedModifier($0, side: finished.pressed.side(of: $0)) }
        guard modifiers.count == 1, let modifier = modifiers.first else {
            lastTap = nil
            return .modifierTap(Set(modifiers))
        }
        if let lastTap, lastTap.modifier == modifier,
           finished.start - lastTap.releasedAt <= Self.doubleTapWindow {
            self.lastTap = nil
            return .doubleTap(modifier)
        }
        lastTap = ModifierTapRecord(modifier: modifier, releasedAt: releasedAt)
        return .modifierTap([modifier])
    }

    private mutating func record(_ spec: HotkeySpec) -> RecorderUpdate {
        recorded = spec
        return .recorded(spec)
    }
}

/// Which modifier keys one flagsChanged event (or a whole hold) has down.
struct HeldModifiers: Equatable, Sendable {
    var modifiers: ModifierSet
    var sides: ModifierSides

    init(modifiers: ModifierSet = [], sides: ModifierSides = []) {
        self.modifiers = modifiers
        self.sides = sides
    }

    init(_ event: KeyEvent) {
        self.init(modifiers: event.modifiers, sides: event.sides)
    }

    var isEmpty: Bool { modifiers.isEmpty && sides.isEmpty }

    /// The modifier keys down, in canonical order (a side bit alone counts).
    var keys: [ModifierKey] {
        ModifierKey.canonicalOrder.filter { modifiers.contains($0.member) || !sides.isDisjoint(with: $0.physicalKeys) }
    }

    /// `.left`/`.right` when exactly that side is down; `.any` for both, neither (no side
    /// information) and fn.
    func side(of key: ModifierKey) -> KeySide {
        guard let left = key.physicalKey(on: .left), let right = key.physicalKey(on: .right) else { return .any }
        switch (sides.contains(left), sides.contains(right)) {
        case (true, false): return .left
        case (false, true): return .right
        default: return .any
        }
    }

    /// Whether both sides of `key` are down.
    func hasBothSides(of key: ModifierKey) -> Bool {
        guard let left = key.physicalKey(on: .left), let right = key.physicalKey(on: .right) else { return false }
        return sides.contains(left) && sides.contains(right)
    }

    /// "⌘", "R⌘" (one side down), "L⌘" "R⌘" (both down), "fn".
    var keycaps: [String] {
        keys.flatMap { key -> [String] in
            if hasBothSides(of: key) {
                return [SidedModifier(key, side: .left).keycap, SidedModifier(key, side: .right).keycap]
            }
            return [SidedModifier(key, side: side(of: key)).keycap]
        }
    }
}

/// One stretch of modifier keys held down, from the first press until every one is up.
struct ModifierHold: Equatable, Sendable {
    /// When the first modifier went down.
    var start: TimeInterval
    /// Every modifier key and side down at any point.
    var pressed = HeldModifiers()
    /// Modifiers whose left and right keys were down at the same time.
    var bothDown: Set<ModifierKey> = []
    /// A non-modifier key went down during the hold.
    var keyWentDown = false

    init(start: TimeInterval) {
        self.start = start
    }

    mutating func add(_ held: HeldModifiers) {
        pressed.modifiers.formUnion(held.modifiers)
        pressed.sides.formUnion(held.sides)
        for key in held.keys where held.hasBothSides(of: key) {
            bothDown.insert(key)
        }
    }
}

/// A clean single-modifier tap: the modifier as pressed and when it was released.
struct ModifierTapRecord: Equatable, Sendable {
    var modifier: SidedModifier
    var releasedAt: TimeInterval
}
