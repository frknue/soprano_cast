import AppKit
import Carbon
import SopranoCastCore

/// Combo hotkeys through Carbon's `RegisterEventHotKey`: no Accessibility needed, and they
/// fire even while Soprano Cast's own panel is key. One `kEventHotKeyPressed` handler on the
/// application event target dispatches by hotkey id.
///
/// Character keys resolve to key codes on the current layout at registration, so every
/// registration is redone when the selected input source changes.
///
/// The event handler's user data is a retained reference to this object, released never:
/// it lives for the whole process, like the handler.
@MainActor
final class CarbonHotkeys {
    /// One combo to register: the binding it reports and the resolved modifiers (Hyper
    /// expanded) and key.
    struct Request {
        var binding: HotkeyBinding
        var modifiers: ModifierSet
        var key: KeySpec
    }

    /// Called on the main actor when a registered hotkey is pressed.
    var onPress: ((HotkeyTarget) -> Void)?

    private var requests: [Request] = []
    private var registered: [UInt32: (ref: EventHotKeyRef, target: HotkeyTarget)] = [:]
    private var nextID: UInt32 = 1
    private var isActive = false
    private var handlerInstalled = false
    private var inputSourceObserver: NSObjectProtocol?

    /// 'SCst'.
    private static let signature: OSType = 0x5343_7374

    init() {}

    /// Replaces every request and registers them now unless `suspended`. Returns the
    /// requests that could not be registered (registration is attempted even when
    /// suspended, then undone, so the failures are always current).
    func setRequests(_ requests: [Request], suspended: Bool) -> [HotkeyFailure] {
        self.requests = requests
        installHandlerIfNeeded()
        observeInputSourceIfNeeded()
        let failures = registerAll()
        if suspended { unregisterAll() }
        return failures
    }

    /// Registers every request (after dropping the current registrations).
    @discardableResult
    func registerAll() -> [HotkeyFailure] {
        unregisterAll()
        isActive = true
        let reserved = Self.systemHotkeys()
        var failures: [HotkeyFailure] = []
        for request in requests {
            let keyCode: UInt16
            switch request.key {
            case .named(let named):
                keyCode = named.keyCodes[0]
            case .character(let character):
                guard let code = KeyboardLayout.keyCode(for: character) else {
                    failures.append(HotkeyFailure(binding: request.binding, reason: "no key types \(character) on this layout"))
                    continue
                }
                keyCode = code
            }
            let modifiers = Self.carbonModifiers(request.modifiers)
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
            )
            guard status == noErr, let ref else {
                failures.append(HotkeyFailure(binding: request.binding, reason: Self.reason(for: status)))
                continue
            }
            registered[nextID] = (ref, request.binding.target)
            nextID &+= 1
            // A system shortcut (Spotlight's ⌘Space, Mission Control's ⌃↑) takes the press
            // first while it is enabled; the registration stays so the hotkey works as
            // soon as it is turned off in System Settings.
            if reserved.contains(SystemHotkey(keyCode: keyCode, modifiers: modifiers)) {
                failures.append(HotkeyFailure(binding: request.binding, reason: "used by macOS"))
            }
        }
        return failures
    }

    /// Unregisters every hotkey; `registerAll()` restores them.
    func unregisterAll() {
        isActive = false
        for entry in registered.values {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    fileprivate func pressed(id: UInt32) {
        guard let target = registered[id]?.target else { return }
        onPress?(target)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passRetained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), carbonHotkeyHandler, 1, &eventType, userData, nil)
        if status == noErr {
            handlerInstalled = true
        } else {
            Unmanaged<CarbonHotkeys>.fromOpaque(userData).release()
        }
    }

    private func observeInputSourceIfNeeded() {
        guard inputSourceObserver == nil else { return }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.registerAll()
            }
        }
    }

    private static func carbonModifiers(_ modifiers: ModifierSet) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    private static func reason(for status: OSStatus) -> String {
        switch status {
        case OSStatus(eventHotKeyExistsErr): "already registered"
        case OSStatus(eventHotKeyInvalidErr): "not a valid hotkey"
        default: "couldn't register (error \(status))"
        }
    }

    /// An enabled macOS keyboard shortcut (System Settings › Keyboard › Keyboard Shortcuts)
    /// as a key code plus Carbon modifier mask.
    private struct SystemHotkey: Hashable {
        var keyCode: UInt16
        var modifiers: UInt32
    }

    private static func systemHotkeys() -> Set<SystemHotkey> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = (unmanaged?.takeRetainedValue() as NSArray?) as? [[String: Any]] else {
            return []
        }
        let carbonMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        var result: Set<SystemHotkey> = []
        for entry in entries {
            guard (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let code = (entry["kHISymbolicHotKeyCode"] as? NSNumber)?.intValue,
                  (0..<128).contains(code),
                  let rawModifiers = (entry["kHISymbolicHotKeyModifiers"] as? NSNumber)?.uint32Value else {
                continue
            }
            result.insert(SystemHotkey(keyCode: UInt16(code), modifiers: rawModifiers & carbonMask))
        }
        return result
    }
}

/// The Carbon event handler. Carbon dispatches application-target events on the main
/// thread; only the hotkey id and the object's address cross into the main actor.
private func carbonHotkeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == 0x5343_7374 else { return OSStatus(eventNotHandledErr) }
    let address = Int(bitPattern: userData)
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<CarbonHotkeys>.fromOpaque(pointer).takeUnretainedValue().pressed(id: id)
    }
    return noErr
}
