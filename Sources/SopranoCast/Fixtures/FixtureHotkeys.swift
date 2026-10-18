import AppKit
import SopranoCastCore

/// Records hotkey registrations instead of registering them; nothing ever fires.
@MainActor
final class FixtureHotkeys: HotkeyRegistering {
    /// The bindings of the last `setBindings` call.
    private(set) var bindings: [HotkeyBinding] = []
    private(set) var hyperKey = HyperKeySettings()
    private(set) var isSuspended = false
    /// "setBindings 3", "suspend", "resume", in call order.
    private(set) var log: [String] = []
    var onTrigger: ((HotkeyTarget) -> Void)?

    init() {}

    @discardableResult
    func setBindings(_ bindings: [HotkeyBinding], hyperKey: HyperKeySettings) -> [HotkeyFailure] {
        self.bindings = bindings
        self.hyperKey = hyperKey
        log.append("setBindings \(bindings.count)")
        return []
    }

    func suspend() {
        isSuspended = true
        log.append("suspend")
    }

    func resume() {
        isSuspended = false
        log.append("resume")
    }
}
