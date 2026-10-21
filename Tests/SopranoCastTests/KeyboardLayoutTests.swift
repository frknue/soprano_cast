import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct KeyboardLayoutTests {
    @Test("the number row's 1 key types 1 on the current layout and back")
    func digitRoundTrip() {
        #expect(KeyboardLayout.keyCode(for: "1") == 0x12)
        #expect(KeyboardLayout.character(for: 0x12) == "1")
    }

    @Test("every digit resolves to a key that types it")
    func allDigits() {
        for digit in "0123456789" {
            let code = KeyboardLayout.keyCode(for: digit)
            #expect(code != nil)
            if let code {
                #expect(KeyboardLayout.character(for: code) == digit)
            }
        }
    }

    @Test("keys that type nothing printable have no character")
    func nonPrintingKeys() {
        #expect(KeyboardLayout.character(for: 0x24) == nil) // Return
        #expect(KeyboardLayout.character(for: 0x7B) == nil) // ←
    }

    @Test("a physical key's keycap is what it types on the current layout")
    func physicalKeycap() {
        #expect(KeyboardLayout.keycapSymbol(for: .physical(0x12)) == "1")
    }

    @Test("named keys keep the Core symbol as their keycap")
    func namedKeycap() {
        #expect(KeyboardLayout.keycapSymbol(for: .named(.return)) == KeySpec.named(.return).symbol)
    }

    @Test("combo keycaps show a physical key through the layout, modifiers unchanged")
    func comboKeycaps() {
        let spec = HotkeySpec.combo(HotkeyCombo(modifiers: [.command], key: .physical(0x12)))
        let keycaps = KeyboardLayout.keycaps(for: spec)
        #expect(keycaps.count == spec.keycaps.count)
        #expect(keycaps.last == "1")
        #expect(Array(keycaps.dropLast()) == Array(spec.keycaps.dropLast()))
    }

    @Test("modifier-only specs keep their Core keycaps")
    func tapKeycaps() {
        let spec = HotkeySpec.doubleTap(SidedModifier(.command))
        #expect(KeyboardLayout.keycaps(for: spec) == spec.keycaps)
    }

    @Test("K1 caps join the layout's keycaps into one chord cap")
    func layoutCaps() {
        let spec = HotkeySpec.combo(HotkeyCombo(modifiers: [.shift, .command], key: .physical(0x12)))
        #expect(KeyboardLayout.caps(for: spec) == ["⇧⌘1"])
        #expect(KeyboardLayout.caps(for: .doubleTap(SidedModifier(.command))) == ["⌘", "⌘"])
    }
}
