import AppKit
import Testing
@testable import SopranoCast

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
}
