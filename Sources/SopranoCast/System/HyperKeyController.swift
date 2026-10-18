import AppKit
import ApplicationServices
import IOKit
import IOKit.hidsystem
import SopranoCastCore

/// The Hyper key. `hidutil` remaps the trigger key to F18 at the HID level; an active
/// session event tap then swallows F18 and, while it is held, adds ⌃⌥⇧⌘ (⌃⌥⌘ without
/// Shift) to every keyDown and keyUp, so Carbon hotkeys registered with those modifiers
/// fire. F18 pressed and released with no other key in between performs `quickPress`.
///
/// The user's own `UserKeyMapping` entries are kept: the first `apply` reads them, ours is
/// added for the trigger, and `remove()` puts the original list back (without any stale
/// trigger → F18 entry a crashed earlier run left behind).
@MainActor
final class HyperKeyController {
    private var settings = HyperKeySettings()
    /// The user's mapping before Soprano Cast changed it; nil while ours isn't applied.
    private var originalMapping: [KeyMapping]?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refcon: UnsafeMutableRawPointer?

    private var isHyperDown = false
    private var keyPressedWhileDown = false

    /// kVK_F18.
    private static let f18KeyCode: Int64 = 0x4F
    private static let f18Usage: Int64 = 0x7_0000_006D

    init() {}

    /// Applies `settings` (nil trigger = no Hyper key). Returns an error message for the
    /// menu when the Hyper key can't work, after undoing everything; nil when it works.
    func apply(_ settings: HyperKeySettings) -> String? {
        self.settings = settings
        guard let trigger = settings.trigger else {
            remove()
            return nil
        }
        guard AXIsProcessTrusted() else {
            remove()
            return "Hyper Key needs Accessibility"
        }
        if tap == nil, !startTap() {
            remove()
            return "Hyper Key couldn't start its event tap"
        }
        let original = originalMapping ?? Self.currentMapping().filter { !Self.isOurs($0) }
        var mapping = original
        if let source = Self.sourceUsage(for: trigger) {
            mapping.removeAll { $0.source == source }
            mapping.append(KeyMapping(source: source, destination: Self.f18Usage))
        }
        if let error = Self.setMapping(mapping) {
            remove()
            return "Hyper Key: \(error)"
        }
        originalMapping = original
        return nil
    }

    /// Restores the user's key mapping and stops the tap. Also called on quit.
    func remove() {
        stopTap()
        isHyperDown = false
        keyPressedWhileDown = false
        guard let original = originalMapping else { return }
        originalMapping = nil
        _ = Self.setMapping(original)
    }

    // MARK: - Event tap

    private func startTap() -> Bool {
        let refcon = Unmanaged.passRetained(self).toOpaque()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hyperTapCallback,
            userInfo: refcon
        ) else {
            Unmanaged<HyperKeyController>.fromOpaque(refcon).release()
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        self.refcon = refcon
        return true
    }

    private func stopTap() {
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
            Unmanaged<HyperKeyController>.fromOpaque(refcon).release()
        }
    }

    /// What the tap does with one event.
    fileprivate enum Decision: Sendable {
        case pass
        case swallow
        /// Pass with these flags.
        case setFlags(UInt64)
    }

    /// The Hyper modifiers, as device-independent flag bits. They are OR-ed into the
    /// event's flags, so a modifier the user also holds for real is not added twice and
    /// its device-dependent side bit (left/right) stays as the keyboard reported it.
    private var hyperFlags: CGEventFlags {
        var flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        if settings.includeShift { flags.insert(.maskShift) }
        return flags
    }

    fileprivate func receive(type: CGEventType, keyCode: Int64, isRepeat: Bool, flags: UInt64) -> Decision {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return .pass
        case .keyDown, .keyUp:
            break
        default:
            return .pass
        }
        if keyCode == Self.f18KeyCode {
            if type == .keyDown {
                if !isRepeat {
                    isHyperDown = true
                    keyPressedWhileDown = false
                }
            } else {
                let wasClean = isHyperDown && !keyPressedWhileDown
                isHyperDown = false
                if wasClean { performQuickPress() }
            }
            return .swallow
        }
        guard isHyperDown else { return .pass }
        if type == .keyDown { keyPressedWhileDown = true }
        let current = CGEventFlags(rawValue: flags)
        let combined = current.union(hyperFlags)
        return combined == current ? .pass : .setFlags(combined.rawValue)
    }

    private func performQuickPress() {
        guard settings.trigger == .capsLock else { return }
        switch settings.quickPress {
        case .nothing:
            break
        case .toggleCapsLock:
            Self.toggleCapsLock()
        case .escape:
            Self.postEscape()
        }
    }

    private static func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            return
        }
        defer { IOServiceClose(connect) }
        var isOn = false
        guard IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &isOn) == KERN_SUCCESS else { return }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !isOn)
    }

    /// Posts Escape down and up at the HID level; with F18 already up the tap passes them.
    private static func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: isDown)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - hidutil

    /// One `UserKeyMapping` entry (HID usage page << 32 | usage).
    struct KeyMapping: Equatable {
        var source: Int64
        var destination: Int64
    }

    /// HID usages of the triggers hidutil remaps; F18 itself needs no mapping.
    private static func sourceUsage(for trigger: HyperTrigger) -> Int64? {
        switch trigger {
        case .capsLock: 0x7_0000_0039
        case .rightCommand: 0x7_0000_00E7
        case .rightOption: 0x7_0000_00E6
        case .rightControl: 0x7_0000_00E4
        case .rightShift: 0x7_0000_00E5
        case .f18: nil
        }
    }

    /// A trigger → F18 entry Soprano Cast writes.
    private static func isOurs(_ mapping: KeyMapping) -> Bool {
        mapping.destination == f18Usage
            && HyperTrigger.allCases.compactMap(sourceUsage(for:)).contains(mapping.source)
    }

    /// The current `UserKeyMapping`, printed by hidutil as an old-style property list
    /// (`( { HIDKeyboardModifierMappingDst = …; HIDKeyboardModifierMappingSrc = …; } )`, or
    /// `(null)` when empty).
    private static func currentMapping() -> [KeyMapping] {
        guard let output = runHidutil(["property", "--get", "UserKeyMapping"]).output,
              let data = output.data(using: .utf8),
              let list = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard let source = integer(entry["HIDKeyboardModifierMappingSrc"]),
                  let destination = integer(entry["HIDKeyboardModifierMappingDst"]) else { return nil }
            return KeyMapping(source: source, destination: destination)
        }
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.lowercased().hasPrefix("0x") { return Int64(text.dropFirst(2), radix: 16) }
        return Int64(text)
    }

    /// Replaces `UserKeyMapping`; an empty list clears it. Returns hidutil's error, if any.
    private static func setMapping(_ mapping: [KeyMapping]) -> String? {
        let entries = mapping.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        let json = "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
        let result = runHidutil(["property", "--set", json])
        return result.error
    }

    /// Runs /usr/bin/hidutil synchronously (it returns at once).
    private static func runHidutil(_ arguments: [String]) -> (output: String?, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return (nil, "couldn't run hidutil (\(error.localizedDescription))")
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: outputData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return (output, message.isEmpty ? "hidutil failed (exit \(process.terminationStatus))" : message)
        }
        return (output, nil)
    }
}

/// The C callback. The run-loop source is on the main run loop, so this runs on the main
/// thread; Sendable scalars go into the main actor and a Sendable decision comes back,
/// applied to the event here.
private func hyperTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let address = Int(bitPattern: refcon)
    let isKey = type == .keyDown || type == .keyUp
    let keyCode = isKey ? event.getIntegerValueField(.keyboardEventKeycode) : -1
    let isRepeat = isKey && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let flags = event.flags.rawValue
    let decision = MainActor.assumeIsolated { () -> HyperKeyController.Decision in
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return .pass }
        return Unmanaged<HyperKeyController>.fromOpaque(pointer).takeUnretainedValue()
            .receive(type: type, keyCode: keyCode, isRepeat: isRepeat, flags: flags)
    }
    switch decision {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    case .setFlags(let raw):
        event.flags = CGEventFlags(rawValue: raw)
        return Unmanaged.passUnretained(event)
    }
}
