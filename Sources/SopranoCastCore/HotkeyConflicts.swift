import Foundation

public struct HotkeyConflict: Equatable, Sendable {
    public var spec: HotkeySpec
    public var targets: [HotkeyTarget]
    /// "same" (identical after expanding Hyper) or "cannotCoexist" (⌥ tap vs ⌥⌥ double tap,
    /// any-side ⌘ tap vs both-sided ⌘).
    public var reason: Reason
    public enum Reason: Equatable, Sendable { case same, cannotCoexist }

    public init(spec: HotkeySpec, targets: [HotkeyTarget], reason: Reason) {
        self.spec = spec
        self.targets = targets
        self.reason = reason
    }
}

/// Hotkeys that would fire for the same keystrokes.
///
/// Two specs are the same when they are equal after Hyper expands to its modifiers
/// (`hyper+k` = `ctrl+opt+shift+cmd+k`, or `ctrl+opt+cmd+k` when Hyper excludes Shift).
/// Combo keys are the same when both resolve to the same key code through `keyCode`, or
/// when they are equal; a key resolving to nil compares by equality only. The default
/// resolver knows positions only (`positionalKeyCode`); pass a layout-aware one so a
/// `.character` key meets the `.physical` key that types it.
/// Two specs cannot coexist when one would always fire inside the other's gesture: a single
/// modifier tap vs a double tap of that modifier (tap any side, or the double tap's side or
/// any side), and an any-side tap of a modifier vs both sides of it.
public enum HotkeyConflicts {
    /// `.same` conflicts first (one per spec, targets in binding order, the spec as the first
    /// binding spells it), then one `.cannotCoexist` per pair (the spec of the earlier
    /// binding). Bindings of the same target never conflict with each other.
    public static func conflicts(
        in bindings: [HotkeyBinding], hyperIncludesShift: Bool,
        keyCode: (KeySpec) -> UInt16? = HotkeyConflicts.positionalKeyCode
    ) -> [HotkeyConflict] {
        var same: [HotkeyConflict] = []
        for binding in bindings {
            let index = same.firstIndex {
                isSame($0.spec, binding.spec, hyperIncludesShift: hyperIncludesShift, keyCode: keyCode)
            }
            if let index {
                if !same[index].targets.contains(binding.target) {
                    same[index].targets.append(binding.target)
                }
            } else {
                same.append(HotkeyConflict(spec: binding.spec, targets: [binding.target], reason: .same))
            }
        }

        var coexist: [HotkeyConflict] = []
        for (index, first) in bindings.enumerated() {
            for second in bindings[(index + 1)...]
            where first.target != second.target && cannotCoexist(first.spec, second.spec) {
                let conflict = HotkeyConflict(spec: first.spec, targets: [first.target, second.target], reason: .cannotCoexist)
                if !coexist.contains(conflict) { coexist.append(conflict) }
            }
        }

        return same.filter { $0.targets.count > 1 } + coexist
    }

    /// The target already using `spec` (or one that cannot coexist with it), other than `except`.
    public static func owner(
        of spec: HotkeySpec, in bindings: [HotkeyBinding], except: HotkeyTarget?, hyperIncludesShift: Bool,
        keyCode: (KeySpec) -> UInt16? = HotkeyConflicts.positionalKeyCode
    ) -> HotkeyTarget? {
        bindings.first { binding in
            binding.target != except
                && (isSame(binding.spec, spec, hyperIncludesShift: hyperIncludesShift, keyCode: keyCode)
                    || cannotCoexist(binding.spec, spec))
        }?.target
    }

    /// .physical → its code; .named → its first key code; .character → nil.
    public static func positionalKeyCode(_ key: KeySpec) -> UInt16? {
        switch key {
        case .physical(let code): code
        case .named(let named): named.keyCodes.first
        case .character: nil
        }
    }

    /// Combos: equal effective modifiers and the same key (by resolved code or equality);
    /// other shapes: equality.
    private static func isSame(
        _ first: HotkeySpec, _ second: HotkeySpec, hyperIncludesShift: Bool, keyCode: (KeySpec) -> UInt16?
    ) -> Bool {
        guard case .combo(let lhs) = first, case .combo(let rhs) = second else { return first == second }
        guard lhs.effectiveModifiers(hyperIncludesShift: hyperIncludesShift)
            == rhs.effectiveModifiers(hyperIncludesShift: hyperIncludesShift)
        else { return false }
        if lhs.key == rhs.key { return true }
        guard let lhsCode = keyCode(lhs.key), let rhsCode = keyCode(rhs.key) else { return false }
        return lhsCode == rhsCode
    }

    private static func cannotCoexist(_ first: HotkeySpec, _ second: HotkeySpec) -> Bool {
        oneWayConflict(first, second) || oneWayConflict(second, first)
    }

    private static func oneWayConflict(_ tapSpec: HotkeySpec, _ other: HotkeySpec) -> Bool {
        guard case .modifierTap(let modifiers) = tapSpec, modifiers.count == 1, let tap = modifiers.first else {
            return false
        }
        switch other {
        case .doubleTap(let double):
            return double.key == tap.key && (tap.side == .any || double.side == .any || tap.side == double.side)
        case .bothSides(let key):
            return key == tap.key && tap.side == .any
        case .combo, .modifierTap:
            return false
        }
    }
}
