import AppKit
import Testing
@testable import SopranoCastCore

struct HotkeyParsingTests {
    private struct Case: Sendable {
        var text: String
        var spec: HotkeySpec
        var canonical: String
    }

    private static let cases: [Case] = [
        Case(text: "cmd+shift+k",
             spec: .combo(HotkeyCombo(modifiers: [.command, .shift], key: .character("k"))),
             canonical: "shift+cmd+k"),
        Case(text: " Command + Shift + K ",
             spec: .combo(HotkeyCombo(modifiers: [.command, .shift], key: .character("k"))),
             canonical: "shift+cmd+k"),
        Case(text: "⌘+⇧+k",
             spec: .combo(HotkeyCombo(modifiers: [.command, .shift], key: .character("k"))),
             canonical: "shift+cmd+k"),
        Case(text: "alt+space",
             spec: .combo(HotkeyCombo(modifiers: .option, key: .named(.space))),
             canonical: "opt+space"),
        Case(text: "cmd+1",
             spec: .combo(HotkeyCombo(modifiers: .command, key: .character("1"))),
             canonical: "cmd+1"),
        Case(text: "hyper+1",
             spec: .combo(HotkeyCombo(modifiers: [], usesHyper: true, key: .character("1"))),
             canonical: "hyper+1"),
        Case(text: "cmd+HYPER+k",
             spec: .combo(HotkeyCombo(modifiers: .command, usesHyper: true, key: .character("k"))),
             canonical: "hyper+cmd+k"),
        Case(text: "control+option+left",
             spec: .combo(HotkeyCombo(modifiers: [.control, .option], key: .named(.left))),
             canonical: "ctrl+opt+left"),
        Case(text: "function+a",
             spec: .combo(HotkeyCombo(modifiers: .function, key: .character("a"))),
             canonical: "fn+a"),
        Case(text: "F13",
             spec: .combo(HotkeyCombo(modifiers: [], key: .named(.f13))),
             canonical: "f13"),
        Case(text: "cmd+esc",
             spec: .combo(HotkeyCombo(modifiers: .command, key: .named(.escape))),
             canonical: "cmd+escape"),
        Case(text: "cmd++",
             spec: .combo(HotkeyCombo(modifiers: .command, key: .character("+"))),
             canonical: "cmd++"),
        Case(text: "RCMD",
             spec: .modifierTap([SidedModifier(.command, side: .right)]),
             canonical: "rcmd"),
        Case(text: "lopt",
             spec: .modifierTap([SidedModifier(.option, side: .left)]),
             canonical: "lopt"),
        Case(text: "ralt",
             spec: .modifierTap([SidedModifier(.option, side: .right)]),
             canonical: "ropt"),
        Case(text: "cmd+opt",
             spec: .modifierTap([SidedModifier(.command), SidedModifier(.option)]),
             canonical: "opt+cmd"),
        Case(text: "fn",
             spec: .modifierTap([SidedModifier(.function)]),
             canonical: "fn"),
        Case(text: "double:cmd",
             spec: .doubleTap(SidedModifier(.command)),
             canonical: "double:cmd"),
        Case(text: "Double: rShift",
             spec: .doubleTap(SidedModifier(.shift, side: .right)),
             canonical: "double:rshift"),
        Case(text: "both:command",
             spec: .bothSides(.command),
             canonical: "both:cmd"),
        Case(text: "both:⌥",
             spec: .bothSides(.option),
             canonical: "both:opt"),
    ]

    @Test("every hotkey shape parses, including aliases, and round-trips through its canonical spelling")
    func roundTrips() {
        for testCase in Self.cases {
            let parsed = HotkeySpec(settingsText: testCase.text)
            #expect(parsed == testCase.spec, "\(testCase.text)")
            #expect(parsed?.settingsText == testCase.canonical, "\(testCase.text)")
            #expect(HotkeySpec(settingsText: testCase.canonical) == testCase.spec, "\(testCase.canonical)")
        }
    }

    @Test("malformed hotkeys are rejected")
    func rejections() {
        let rejected = [
            "", "   ", "k", "f12", "space", "both:fn", "both:lcmd", "double:", "double:hyper",
            "cmd+meta", "cmd+k+j", "cmd+kk", "k+cmd", "hyper", "hyper+cmd", "hyper+hyper+k",
            "rcmd+k", "cmd+cmd+k", "lcmd+rcmd", "lfn", "cmd+", "+",
        ]
        for text in rejected {
            #expect(HotkeySpec(settingsText: text) == nil, "\(text)")
        }
    }

    @Test("hyper sets the flag only when written; four explicit modifiers stay explicit")
    func hyperFlag() {
        #expect(HotkeySpec(settingsText: "hyper+k") == .combo(HotkeyCombo(modifiers: [], usesHyper: true, key: .character("k"))))
        #expect(HotkeySpec(settingsText: "cmd+shift+opt+ctrl+k") == .combo(HotkeyCombo(modifiers: .hyper, key: .character("k"))))
        #expect(HotkeySpec(settingsText: "cmd+shift+opt+ctrl+k")?.settingsText == "ctrl+opt+shift+cmd+k")
    }

    @Test("keycaps show each shape in ⌃⌥⇧⌘ order with ✦ for Hyper and L/R for sides")
    func keycaps() {
        let expected: [(String, [String])] = [
            ("cmd+shift+k", ["⇧", "⌘", "K"]),
            ("hyper+1", ["✦", "1"]),
            ("hyper+cmd+k", ["✦", "⌘", "K"]),
            ("ctrl+opt+left", ["⌃", "⌥", "←"]),
            ("fn+a", ["fn", "A"]),
            ("f13", ["F13"]),
            ("rcmd", ["R⌘"]),
            ("cmd+lopt", ["L⌥", "⌘"]),
            ("fn", ["fn"]),
            ("double:cmd", ["⌘", "⌘"]),
            ("double:rshift", ["R⇧", "R⇧"]),
            ("both:cmd", ["L⌘", "R⌘"]),
        ]
        for (text, keycaps) in expected {
            #expect(HotkeySpec(settingsText: text)?.keycaps == keycaps, "\(text)")
        }
    }

    @Test("the display string joins the keycaps")
    func displayString() {
        #expect(HotkeySpec(settingsText: "cmd+shift+k")?.displayString == "⇧⌘K")
        #expect(HotkeySpec(settingsText: "both:cmd")?.displayString == "L⌘R⌘")
        #expect(HotkeySpec(settingsText: "hyper+1")?.displayString == "✦1")
    }
}
