import AppKit
import ApplicationServices
import Darwin

/// The frontmost app's focused window through Accessibility. Every call is a synchronous
/// IPC to the window's app, bounded by `messagingTimeout`, so a hung app costs at most
/// half a second per attribute. Frames are global Quartz coordinates (top-left origin).
@MainActor
struct AXWindow {
    static let messagingTimeout: Float = 0.5

    private static let fullScreenAttribute = "AXFullScreen"

    let element: AXUIElement

    /// The focused window of `NSWorkspace.frontmostApplication`; nil when there is no
    /// frontmost app, it has no focused window, or Accessibility is denied.
    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        return AXWindow(element: window)
    }

    /// The window's CGWindowID (private `_AXUIElementGetWindow`); nil when the symbol is
    /// missing or the element has no window server window.
    var windowID: CGWindowID? {
        guard let function = Self.getWindow else { return nil }
        var id: UInt32 = 0
        guard function(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// kAXPosition + kAXSize.
    var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = value(kAXPositionAttribute),
              AXValueGetType(position) == .cgPoint,
              AXValueGetValue(position, .cgPoint, &origin),
              let dimensions = value(kAXSizeAttribute),
              AXValueGetType(dimensions) == .cgSize,
              AXValueGetValue(dimensions, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var isMovable: Bool { isSettable(kAXPositionAttribute) }

    var isResizable: Bool { isSettable(kAXSizeAttribute) }

    /// Sets position, size, then position again: an app clamps a new size to the display
    /// the window currently is on, so the first move puts it on the target display and the
    /// second fixes the origin once the size has landed. False when the position can't be set.
    @discardableResult
    func setFrame(_ frame: CGRect) -> Bool {
        guard setPosition(frame.origin) else { return false }
        var size = frame.size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
        return setPosition(frame.origin)
    }

    var isFullScreen: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, Self.fullScreenAttribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    var supportsFullScreen: Bool { isSettable(Self.fullScreenAttribute) }

    @discardableResult
    func setFullScreen(_ fullScreen: Bool) -> Bool {
        let value: CFBoolean = fullScreen ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(element, Self.fullScreenAttribute as CFString, value) == .success
    }

    // MARK: - Private

    private func setPosition(_ origin: CGPoint) -> Bool {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private func value(_ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError

    /// `_AXUIElementGetWindow` resolved from every loaded image (RTLD_DEFAULT), so nothing
    /// private is linked and a removed symbol degrades to "no window id".
    private static let getWindow: GetWindowFunction? = {
        let anyImage = UnsafeMutableRawPointer(bitPattern: -2)
        guard let pointer = dlsym(anyImage, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(pointer, to: GetWindowFunction.self)
    }()
}
