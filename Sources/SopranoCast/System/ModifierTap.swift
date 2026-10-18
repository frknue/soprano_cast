import AppKit
import ApplicationServices
import SopranoCastCore

/// Hotkeys Carbon can't register: modifier-only gestures (taps, double taps, both sides) and
/// fn combos. A session event tap at the head of the stream for flagsChanged, keyDown and
/// keyUp, on the main run loop, so the callback runs on the main thread.
///
/// The tap is listen-only while only gestures are bound; an fn combo needs it active so the
/// combo's keyDown (and its keyUp) never reach the focused app. Needs Accessibility.
///
/// While running, the tap's refcon holds a retained reference to this object; `stop()`
/// releases it, so the object stays alive for as long as its tap can call back.
@MainActor
final class ModifierTap {
    /// One fn combo: modifiers as an event reports them (including `.function`, Hyper
    /// expanded) and its key.
    struct FunctionCombo {
        var modifiers: ModifierSet
        var key: KeySpec
        var target: HotkeyTarget
    }

    /// Called on the main actor, after the tap callback returned, when a binding fires.
    var onTrigger: ((HotkeyTarget) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refcon: UnsafeMutableRawPointer?
    private var isListenOnly = true

    private var gestureSpecs: [HotkeySpec] = []
    private var gestureTargets: [HotkeySpec: [HotkeyTarget]] = [:]
    private var detector = ModifierGestureDetector(specs: [])
    private var functionCombos: [FunctionCombo] = []
    /// Key codes whose keyDown the tap swallowed; their keyUp is swallowed too.
    private var swallowedKeyCodes: Set<UInt16> = []
    private var isMuted = false

    init() {}

    /// Replaces what the tap watches and starts, restarts (listen-only ↔ active) or stops
    /// it. Returns nil on success (or with nothing to watch), else the failure reason for
    /// every binding it carries.
    func configure(gestures: [(spec: HotkeySpec, target: HotkeyTarget)], functionCombos: [FunctionCombo]) -> String? {
        gestureSpecs = []
        gestureTargets = [:]
        for gesture in gestures {
            if gestureTargets[gesture.spec] == nil { gestureSpecs.append(gesture.spec) }
            gestureTargets[gesture.spec, default: []].append(gesture.target)
        }
        self.functionCombos = functionCombos
        resetState()

        guard !gestures.isEmpty || !functionCombos.isEmpty else {
            stop()
            return nil
        }
        guard AXIsProcessTrusted() else {
            stop()
            return "needs Accessibility"
        }
        let listenOnly = functionCombos.isEmpty
        if tap != nil, listenOnly == isListenOnly { return nil }
        stop()
        return start(listenOnly: listenOnly) ? nil : "event tap unavailable"
    }

    /// A muted tap passes every event through untouched and fires nothing.
    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        resetState()
    }

    private func resetState() {
        detector = ModifierGestureDetector(specs: gestureSpecs)
        swallowedKeyCodes = []
    }

    private func start(listenOnly: Bool) -> Bool {
        let refcon = Unmanaged.passRetained(self).toOpaque()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: modifierTapCallback,
            userInfo: refcon
        ) else {
            Unmanaged<ModifierTap>.fromOpaque(refcon).release()
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        self.refcon = refcon
        isListenOnly = listenOnly
        return true
    }

    /// Removes the tap; a no-op when it is not running.
    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        if let refcon {
            self.refcon = nil
            Unmanaged<ModifierTap>.fromOpaque(refcon).release()
        }
    }

    /// Returns true to swallow the event (only honored by the active tap). macOS disables a
    /// tap whose callback was too slow or that secure input interrupted; it then sends a
    /// `tapDisabledBy…` event and the tap turns itself back on.
    fileprivate func receive(type: CGEventType, keyEvent: KeyEvent?) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            break
        }
        guard let keyEvent, !isMuted else { return false }

        var swallow = false
        switch keyEvent.kind {
        case .keyDown:
            if let combo = functionCombos.first(where: { $0.modifiers == keyEvent.modifiers && $0.key.matches(keyEvent) }) {
                swallowedKeyCodes.insert(keyEvent.keyCode)
                swallow = true
                if !keyEvent.isRepeat { fire(combo.target) }
            }
        case .keyUp:
            swallow = swallowedKeyCodes.remove(keyEvent.keyCode) != nil
        case .flagsChanged:
            break
        }
        if keyEvent.kind != .keyUp {
            for spec in detector.handle(keyEvent) {
                for target in gestureTargets[spec] ?? [] { fire(target) }
            }
        }
        return swallow && !isListenOnly
    }

    /// Runs the target after the callback returns, so slow work can't time the tap out.
    private func fire(_ target: HotkeyTarget) {
        Task { @MainActor [weak self] in
            self?.onTrigger?(target)
        }
    }
}

/// The C callback. The run-loop source is on the main run loop, so this runs on the main
/// thread; only Sendable values (the converted event, the tap's address) cross into the
/// main actor.
private func modifierTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let address = Int(bitPattern: refcon)
    let keyEvent = KeyEventConversion.keyEvent(from: event, type: type)
    let swallow = MainActor.assumeIsolated { () -> Bool in
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return false }
        return Unmanaged<ModifierTap>.fromOpaque(pointer).takeUnretainedValue().receive(type: type, keyEvent: keyEvent)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
