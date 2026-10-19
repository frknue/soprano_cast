import Foundation

/// One hotkey recording, shared by the launcher's recorder card and the settings window:
/// what the card shows, what was recorded, who already holds it, and what the host does
/// next. The host owns the countdown timer and the settings writes.
public struct HotkeyRecordingSession: Sendable {
    /// A recorded hotkey saves itself after this long.
    public static let countdownMilliseconds = 1500
    /// The countdown bar advances this often.
    public static let tickMilliseconds = 100

    /// The keycaps the card shows.
    public enum Keys: Equatable, Sendable {
        /// A hotkey (the current one, or what was just recorded), drawn with the layout's keycaps.
        case spec(HotkeySpec)
        /// The recorder's own keycaps while modifiers are held.
        case display([String])
    }

    /// What the host does after an event.
    public enum Step: Equatable, Sendable {
        /// Nothing visible changed.
        case none
        /// Show the new keys; a running countdown stops.
        case redraw
        /// A hotkey that can be saved was recorded: show it and start the countdown.
        case startCountdown
        /// Write `spec` for the target, first removing it from `takingFrom`; close.
        case save(HotkeySpec, takingFrom: HotkeyTarget?)
        /// Remove the target's hotkey; close.
        case clear
        /// Close without writing.
        case close
    }

    /// The launcher (its own hotkey) or the item being recorded for.
    public let target: HotkeyTarget
    public private(set) var keys: Keys
    /// The last complete hotkey; nil while nothing was recorded or a new hold began.
    public private(set) var recorded: HotkeySpec?
    /// The other target already using `recorded`.
    public private(set) var owner: HotkeyTarget?
    private var recorder = HotkeyRecorder()

    /// Starts on the target's current hotkey (shown until the first key goes down).
    public init(target: HotkeyTarget, current: HotkeySpec?) {
        self.target = target
        keys = current.map { .spec($0) } ?? .display([])
    }

    /// Feeds one keyDown, keyUp or flagsChanged. `owner` names the target (other than this
    /// session's) that already uses a hotkey.
    public mutating func handle(_ event: KeyEvent, owner: (HotkeySpec) -> HotkeyTarget?) -> Step {
        switch recorder.handle(event) {
        case .pending(let display):
            // A new hold: what was recorded is being replaced.
            keys = .display(display)
            recorded = nil
            self.owner = nil
            return .redraw
        case .recorded(let spec):
            recorded = spec
            keys = .spec(spec)
            self.owner = owner(spec)
            // The launcher's own hotkey can't be taken, so there is nothing to count down to.
            return self.owner == .launcher ? .redraw : .startCountdown
        case .cleared:
            return .clear
        case .cancelled:
            return .close
        case .commit:
            return commit(owner: owner)
        case .unchanged:
            return .none
        }
    }

    /// ↵ or the end of the countdown: saves what was recorded (taking it from its owner),
    /// closes when nothing was, and does nothing while the launcher holds it.
    public func commit(owner: (HotkeySpec) -> HotkeyTarget?) -> Step {
        guard let recorded else { return .close }
        let holder = owner(recorded)
        guard holder != .launcher else { return .none }
        return .save(recorded, takingFrom: holder)
    }
}
