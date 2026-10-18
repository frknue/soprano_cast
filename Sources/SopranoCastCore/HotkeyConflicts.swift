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
/// Two specs cannot coexist when one would always fire inside the other's gesture: a single
/// modifier tap vs a double tap of that modifier (tap any side, or the double tap's side or
/// any side), and an any-side tap of a modifier vs both sides of it.
public enum HotkeyConflicts {
    /// `.same` conflicts first (one per spec, targets in binding order, the spec as the first
    /// binding spells it), then one `.cannotCoexist` per pair (the spec of the earlier
    /// binding). Bindings of the same target never conflict with each other.
    public static func conflicts(in bindings: [HotkeyBinding], hyperIncludesShift: Bool) -> [HotkeyConflict] {
        var same: [HotkeyConflict] = []
        var groupIndex: [HotkeySpec: Int] = [:]
        for binding in bindings {
            let normalized = normalize(binding.spec, hyperIncludesShift: hyperIncludesShift)
            if let index = groupIndex[normalized] {
                if !same[index].targets.contains(binding.target) {
                    same[index].targets.append(binding.target)
                }
            } else {
                groupIndex[normalized] = same.count
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
    public static func owner(of spec: HotkeySpec, in bindings: [HotkeyBinding], except: HotkeyTarget?, hyperIncludesShift: Bool) -> HotkeyTarget? {
        let normalized = normalize(spec, hyperIncludesShift: hyperIncludesShift)
        return bindings.first { binding in
            binding.target != except
                && (normalize(binding.spec, hyperIncludesShift: hyperIncludesShift) == normalized
                    || cannotCoexist(binding.spec, spec))
        }?.target
    }

    /// Combos with Hyper expanded into plain modifiers; other shapes unchanged.
    private static func normalize(_ spec: HotkeySpec, hyperIncludesShift: Bool) -> HotkeySpec {
        guard case .combo(let combo) = spec else { return spec }
        return .combo(HotkeyCombo(modifiers: combo.effectiveModifiers(hyperIncludesShift: hyperIncludesShift), key: combo.key))
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
