import AppKit
import Carbon
import SopranoCastCore

/// Characters ↔ key codes on the current keyboard layout. Main thread only (the Text Input
/// Sources API reads the selected input source).
enum KeyboardLayout {
    /// The key code that types `character` (lowercased) with no modifiers on the current
    /// layout (UCKeyTranslate over codes 0…127), nil when none does. The lowest code wins,
    /// so "1" is the number row's key, not the keypad's.
    static func keyCode(for character: Character) -> UInt16? {
        let wanted = String(character).lowercased()
        guard let layout = currentLayoutData() else { return nil }
        return layout.withUnsafeBytes { buffer -> UInt16? in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            let keyboardType = UInt32(LMGetKbdType())
            for code in UInt16(0)..<128 {
                if let typed = translate(code, layout: pointer, keyboardType: keyboardType),
                   String(typed).lowercased() == wanted {
                    return code
                }
            }
            return nil
        }
    }

    /// The character key code `keyCode` types with no modifiers on the current layout; nil
    /// for keys that type nothing printable (Return, Tab, arrows, F keys).
    static func character(for keyCode: UInt16) -> Character? {
        guard let layout = currentLayoutData() else { return nil }
        return layout.withUnsafeBytes { buffer -> Character? in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            return translate(keyCode, layout: pointer, keyboardType: UInt32(LMGetKbdType()))
        }
    }

    /// The keycap for `key`: a physical key shows what it types on the current layout,
    /// uppercased ("Ä" on German for the key ABC types "'" on), falling back to the Core
    /// symbol when it types nothing printable; named and character keys show `key.symbol`.
    static func keycapSymbol(for key: KeySpec) -> String {
        guard case .physical(let code) = key, let character = character(for: code) else {
            return key.symbol
        }
        return String(character).uppercased()
    }

    /// `spec.keycaps` with a combo's key shown through `keycapSymbol(for:)`; modifier-only
    /// specs unchanged.
    static func keycaps(for spec: HotkeySpec) -> [String] {
        var keycaps = spec.keycaps
        if case .combo(let combo) = spec, !keycaps.isEmpty {
            keycaps[keycaps.count - 1] = keycapSymbol(for: combo.key)
        }
        return keycaps
    }

    /// The 'uchr' data of the current keyboard layout. Input methods without one (some
    /// CJK input sources) fall back to the ASCII-capable layout they type through.
    private static func currentLayoutData() -> Data? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        ]
        for case let source? in sources {
            if let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            }
        }
        return nil
    }

    /// What `keyCode` types with no modifiers, dead keys shown as their own character.
    /// Control characters (Return, Tab, Escape, function-key private codes) are nil.
    private static func translate(
        _ keyCode: UInt16,
        layout: UnsafePointer<UCKeyboardLayout>,
        keyboardType: UInt32
    ) -> Character? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            units.count,
            &length,
            &units
        )
        guard status == noErr, length > 0 else { return nil }
        let text = String(decoding: units.prefix(length), as: UTF16.self)
        guard text.count == 1, let character = text.first,
              !character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              !character.isWhitespace else {
            return nil
        }
        return character
    }
}
