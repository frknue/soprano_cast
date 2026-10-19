import AppKit
import SopranoCastCore

// Seams between the live macOS layer (System/), the launcher (Launcher/) and the fixtures
// (Fixtures/). The launcher only talks to these protocols, so the snapshot harness and the
// tests run it on fixtures without permissions, real apps or real hotkeys.

/// A live list of items of one kind (applications, script commands).
@MainActor
protocol ItemSource: AnyObject {
    var items: [CastItem] { get }
    /// Called on the main actor after `items` changed (coalesced).
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Images for item icons.
@MainActor
protocol IconProviding: AnyObject {
    /// An image for `icon` at `size` points; never fails (falls back to a glyph). Remote
    /// icons return a placeholder at once and call `onLoad` when the real one is cached.
    func image(for icon: ItemIcon, size: CGFloat) -> NSImage
    var onLoad: (() -> Void)? { get set }
}

/// Runs items and item actions.
@MainActor
protocol ItemRunning: AnyObject {
    /// Runs the item's primary behavior with its argument values (in `arguments` order).
    /// `completion` runs on the main actor, possibly later (scripts).
    func run(_ item: CastItem, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void)
    /// Runs an Action Panel action that is not about settings (open, reveal, copy, quit, hide,
    /// edit script). Settings actions (favorites, hotkeys, aliases, disable) are the
    /// launcher controller's.
    func perform(_ action: ItemActionID, on item: CastItem) -> RunOutcome
    /// Whether an application item's app is running (the Action Panel offers Quit/Hide then).
    func isRunning(_ item: CastItem) -> Bool
}

/// Global hotkeys.
@MainActor
protocol HotkeyRegistering: AnyObject {
    /// Replaces every registration. Returns the bindings that could not be registered with
    /// a reason ("needs Accessibility", "used by macOS", …).
    @discardableResult
    func setBindings(_ bindings: [HotkeyBinding], hyperKey: HyperKeySettings) -> [HotkeyFailure]
    /// Called on the main actor when a binding fires.
    var onTrigger: ((HotkeyTarget) -> Void)? { get set }
    /// Stops every hotkey from firing (while the recorder records) until `resume()`.
    func suspend()
    func resume()
}

struct HotkeyFailure: Equatable {
    var binding: HotkeyBinding
    var reason: String
}

/// Window management on the focused window.
@MainActor
protocol WindowManaging: AnyObject {
    /// Applies `command` to the frontmost app's focused window. Returns a message for the
    /// HUD when nothing could be done ("No focused window", "Window Management needs Accessibility").
    func perform(_ command: WindowCommand, settings: WindowManagementSettings) -> String?
}
