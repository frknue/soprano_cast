import Foundation

/// Watches flagsChanged / keyDown events for modifier-only hotkeys (Raycast's modifier taps,
/// double taps and both-sided modifiers).
///
/// - A tap fires on the release of its last modifier when exactly its modifiers went down
///   (`.any` matches either side, a pinned side only that side; a modifier held on both
///   sides is no tap), no other key went down, and press→release ≤ `maxTapDuration`.
/// - A double tap fires on the second such tap of its modifier when that tap's press comes
///   within `HotkeyRecorder.doubleTapWindow` after the first one's release.
/// - Both-sides fires once, when the second side goes down, if nothing else is held or was
///   pressed since the first modifier went down; that hold then fires no tap.
/// - Any non-modifier keyDown cancels the hold in progress and a pending double tap.
public struct ModifierGestureDetector: Sendable {
    public static let maxTapDuration: TimeInterval = 0.5

    /// The watched specs, deduplicated, in the order given.
    private let specs: [HotkeySpec]
    private var hold: ModifierHold?
    /// Whether a both-sides spec already fired during the current hold.
    private var bothSidesFired = false
    /// The last clean single-modifier tap, as pressed.
    private var lastTap: ModifierTapRecord?

    /// Only `.modifierTap`, `.doubleTap`, `.bothSides` specs are watched; others ignored.
    public init(specs: [HotkeySpec]) {
        var unique: [HotkeySpec] = []
        for spec in specs where !unique.contains(spec) {
            if case .combo = spec { continue }
            unique.append(spec)
        }
        self.specs = unique
    }

    /// Feed every flagsChanged / keyDown (timestamps matter); returns the specs that fired.
    public mutating func handle(_ event: KeyEvent) -> [HotkeySpec] {
        switch event.kind {
        case .keyUp:
            return []
        case .keyDown:
            hold?.keyWentDown = true
            lastTap = nil
            return []
        case .flagsChanged:
            let held = HeldModifiers(event)
            return held.isEmpty ? release(at: event.timestamp) : press(held, at: event.timestamp)
        }
    }

    private mutating func press(_ held: HeldModifiers, at timestamp: TimeInterval) -> [HotkeySpec] {
        if hold == nil {
            hold = ModifierHold(start: timestamp)
            bothSidesFired = false
        }
        hold?.add(held)
        guard let hold, !hold.keyWentDown, !bothSidesFired else { return [] }

        let keys = hold.pressed.keys
        guard keys.count == 1, let key = keys.first, held.hasBothSides(of: key) else { return [] }
        let fired = specs.filter { $0 == .bothSides(key) }
        if !fired.isEmpty {
            bothSidesFired = true
            lastTap = nil
        }
        return fired
    }

    private mutating func release(at timestamp: TimeInterval) -> [HotkeySpec] {
        guard let finished = hold else { return [] }
        hold = nil
        guard !finished.keyWentDown, !bothSidesFired, finished.bothDown.isEmpty,
              timestamp - finished.start <= Self.maxTapDuration
        else {
            lastTap = nil
            return []
        }

        let pressed = finished.pressed.keys.map { SidedModifier($0, side: finished.pressed.side(of: $0)) }
        let previousTap = lastTap
        lastTap = pressed.count == 1 ? ModifierTapRecord(modifier: pressed[0], releasedAt: timestamp) : nil

        var fired: [HotkeySpec] = []
        for spec in specs {
            switch spec {
            case .modifierTap(let modifiers):
                if Self.tap(of: modifiers, matches: pressed) { fired.append(spec) }
            case .doubleTap(let modifier):
                guard pressed.count == 1, let previousTap,
                      Self.modifier(modifier, matches: pressed[0]),
                      Self.modifier(modifier, matches: previousTap.modifier),
                      finished.start - previousTap.releasedAt <= HotkeyRecorder.doubleTapWindow
                else { continue }
                fired.append(spec)
                // The second tap completed the pair; a third starts a new one.
                lastTap = nil
            case .combo, .bothSides:
                continue
            }
        }
        return fired
    }

    /// Whether the spec's modifiers are exactly the pressed ones.
    private static func tap(of modifiers: Set<SidedModifier>, matches pressed: [SidedModifier]) -> Bool {
        guard modifiers.count == pressed.count else { return false }
        return pressed.allSatisfy { physical in
            modifiers.contains { Self.modifier($0, matches: physical) }
        }
    }

    /// `.any` matches either side; a pinned side matches only that side.
    private static func modifier(_ spec: SidedModifier, matches physical: SidedModifier) -> Bool {
        spec.key == physical.key && (spec.side == .any || spec.side == physical.side)
    }
}
