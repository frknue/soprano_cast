import Foundation

// settings.json spellings and keycaps for hotkeys (HotkeySpec and its parts in Keys.swift).

extension SidedModifier {
    /// A modifier name ("cmd", "option", "⌥", …) or a sided one: "l"/"r" + a spelled-out
    /// name ("lcmd", "rcmd", "lopt", "ralt", "lctrl", "rshift", …). fn has no sides.
    /// Case-insensitive; nil for anything else.
    public init?(settingsText: String) {
        let lowered = settingsText.lowercased()
        if let key = ModifierKey(settingsName: lowered) {
            self.init(key)
            return
        }
        guard let first = lowered.first, first == "l" || first == "r",
              let key = ModifierKey(settingsName: String(lowered.dropFirst())),
              key != .function,
              lowered.dropFirst().allSatisfy(\.isLetter)
        else { return nil }
        self.init(key, side: first == "l" ? .left : .right)
    }

    /// "cmd", "lcmd", "rcmd".
    public var settingsText: String {
        switch side {
        case .any: key.settingsName
        case .left: "l" + key.settingsName
        case .right: "r" + key.settingsName
        }
    }

    /// "⌘", "L⌘", "R⌘".
    public var keycap: String {
        switch side {
        case .any: key.symbol
        case .left: "L" + key.symbol
        case .right: "R" + key.symbol
        }
    }

    /// Canonical order: ⌃⌥⇧⌘fn, and within one modifier any, left, right.
    static func canonicallyOrdered(_ modifiers: some Sequence<SidedModifier>) -> [SidedModifier] {
        let sideOrder: [KeySide] = [.any, .left, .right]
        return modifiers.sorted { lhs, rhs in
            let lhsKey = ModifierKey.canonicalOrder.firstIndex(of: lhs.key) ?? 0
            let rhsKey = ModifierKey.canonicalOrder.firstIndex(of: rhs.key) ?? 0
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return (sideOrder.firstIndex(of: lhs.side) ?? 0) < (sideOrder.firstIndex(of: rhs.side) ?? 0)
        }
    }
}

extension HotkeySpec {
    /// Grammar (case-insensitive, spaces ignored):
    ///   combo:   modifiers "+" key       "cmd+shift+k", "hyper+1", "ctrl+opt+left", "fn+a"
    ///            key alone (F13–F20)     "f13"
    ///   taps:    modifiers only          "rcmd", "lopt", "cmd+opt", "fn"
    ///            (sided names lcmd rcmd lopt ropt lctrl rctrl lshift rshift; plain = any side)
    ///   double:  "double:" modifier      "double:cmd", "double:rshift"
    ///   both:    "both:" modifier        "both:cmd" (not fn)
    /// "hyper" sets `usesHyper` (combos only). nil for anything else, including a combo with
    /// no modifier whose key is not F13–F20.
    ///
    /// The key comes last ("cmd++" is ⌘ and the plus key); each modifier appears at most
    /// once; combos take plain (side-less) modifier names only.
    public init?(settingsText: String) {
        let compact = settingsText.filter { !$0.isWhitespace }.lowercased()
        guard !compact.isEmpty else { return nil }

        if compact.hasPrefix("double:") {
            guard let modifier = SidedModifier(settingsText: String(compact.dropFirst("double:".count))) else {
                return nil
            }
            self = .doubleTap(modifier)
            return
        }
        if compact.hasPrefix("both:") {
            guard let key = ModifierKey(settingsName: String(compact.dropFirst("both:".count))),
                  key != .function
            else { return nil }
            self = .bothSides(key)
            return
        }

        var parts = compact.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        if compact.hasSuffix("++") {
            parts.removeLast(2)
            parts.append("+")
        }

        var usesHyper = false
        var modifiers: [SidedModifier] = []
        var key: KeySpec?
        for (index, part) in parts.enumerated() {
            if part == "hyper" {
                guard !usesHyper else { return nil }
                usesHyper = true
            } else if let modifier = SidedModifier(settingsText: part) {
                guard !modifiers.contains(where: { $0.key == modifier.key }) else { return nil }
                modifiers.append(modifier)
            } else {
                guard index == parts.count - 1, let parsed = KeySpec(settingsText: part) else { return nil }
                key = parsed
            }
        }

        if let key {
            guard modifiers.allSatisfy({ $0.side == .any }) else { return nil }
            let modifierSet = ModifierSet(modifiers.map { $0.key.member })
            if modifierSet.isEmpty && !usesHyper {
                guard case .named(let named) = key, named.canStandAlone else { return nil }
            }
            self = .combo(HotkeyCombo(modifiers: modifierSet, usesHyper: usesHyper, key: key))
        } else {
            guard !usesHyper, !modifiers.isEmpty else { return nil }
            self = .modifierTap(Set(modifiers))
        }
    }

    /// Canonical spelling: "hyper" first, then ctrl, opt, shift, cmd, fn, then the key.
    public var settingsText: String {
        switch self {
        case .combo(let combo):
            let parts = (combo.usesHyper ? ["hyper"] : [])
                + combo.modifiers.keys.map(\.settingsName)
                + [combo.key.settingsText]
            return parts.joined(separator: "+")
        case .modifierTap(let modifiers):
            return SidedModifier.canonicallyOrdered(modifiers).map(\.settingsText).joined(separator: "+")
        case .doubleTap(let modifier):
            return "double:" + modifier.settingsText
        case .bothSides(let key):
            return "both:" + key.settingsName
        }
    }

    /// Keycaps: ["⇧","⌘","K"], ["✦","1"] (✦ = Hyper), ["R⌘"], ["⌘","⌘"] (double),
    /// ["L⌘","R⌘"] (both). Modifiers in ⌃⌥⇧⌘fn order.
    public var keycaps: [String] {
        switch self {
        case .combo(let combo):
            return (combo.usesHyper ? ["✦"] : []) + combo.modifiers.symbols + [combo.key.symbol]
        case .modifierTap(let modifiers):
            return SidedModifier.canonicallyOrdered(modifiers).map(\.keycap)
        case .doubleTap(let modifier):
            return [modifier.keycap, modifier.keycap]
        case .bothSides(let key):
            return ["L" + key.symbol, "R" + key.symbol]
        }
    }

    /// Shape names for messages: "⇧⌘K".
    public var displayString: String {
        keycaps.joined()
    }
}
