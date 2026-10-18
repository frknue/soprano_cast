import AppKit
import SopranoCastCore

/// Every global hotkey. Combos without fn go to Carbon (`CarbonHotkeys`: no Accessibility
/// needed, fire while the launcher is key); modifier-only gestures and fn combos go to an
/// event tap (`ModifierTap`: needs Accessibility). Hyper combos register with the Hyper
/// key's modifiers expanded; `HyperKeyController` makes the Hyper key produce them.
///
/// `suspend()` unregisters every Carbon hotkey and mutes the tap, so the hotkey recorder
/// receives ⌘1 itself instead of Chrome opening; `resume()` registers them again.
@MainActor
final class HotkeyCenter: HotkeyRegistering {
    var onTrigger: ((HotkeyTarget) -> Void)?

    private let carbon = CarbonHotkeys()
    private let modifierTap = ModifierTap()
    private var isSuspended = false

    init() {
        carbon.onPress = { [weak self] target in self?.onTrigger?(target) }
        modifierTap.onTrigger = { [weak self] target in self?.onTrigger?(target) }
    }

    @discardableResult
    func setBindings(_ bindings: [HotkeyBinding], hyperKey: HyperKeySettings) -> [HotkeyFailure] {
        var carbonRequests: [CarbonHotkeys.Request] = []
        var tapBindings: [HotkeyBinding] = []
        var gestures: [(spec: HotkeySpec, target: HotkeyTarget)] = []
        var functionCombos: [ModifierTap.FunctionCombo] = []

        for binding in bindings {
            switch binding.spec {
            case .combo(let combo):
                let modifiers = combo.effectiveModifiers(hyperIncludesShift: hyperKey.includeShift)
                if modifiers.contains(.function) {
                    functionCombos.append(.init(modifiers: modifiers, key: combo.key, target: binding.target))
                    tapBindings.append(binding)
                } else {
                    carbonRequests.append(.init(binding: binding, modifiers: modifiers, key: combo.key))
                }
            case .modifierTap, .doubleTap, .bothSides:
                gestures.append((binding.spec, binding.target))
                tapBindings.append(binding)
            }
        }

        var failures = carbon.setRequests(carbonRequests, suspended: isSuspended)
        if let reason = modifierTap.configure(gestures: gestures, functionCombos: functionCombos) {
            failures += tapBindings.map { HotkeyFailure(binding: $0, reason: reason) }
        }
        modifierTap.setMuted(isSuspended)
        // Report in settings order.
        let order = Dictionary(bindings.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return failures.sorted { (order[$0.binding] ?? 0) < (order[$1.binding] ?? 0) }
    }

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        carbon.unregisterAll()
        modifierTap.setMuted(true)
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        carbon.registerAll()
        modifierTap.setMuted(false)
    }
}
