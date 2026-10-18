import AppKit
import Testing
@testable import SopranoCastCore

struct KeyParsingTests {
    @Test("modifier aliases, symbols and spacing parse to one canonical spelling")
    func modifierAliases() {
        #expect(ModifierSet(settingsText: "alt") == .option)
        #expect(ModifierSet(settingsText: "⌥") == .option)
        #expect(ModifierSet(settingsText: "command") == .command)
        #expect(ModifierSet(settingsText: "⌘+⇧") == [.command, .shift])
        #expect(ModifierSet(settingsText: " Cmd + SHIFT ") == [.command, .shift])
        #expect(ModifierSet(settingsText: "function+control") == [.function, .control])

        let all: ModifierSet = [.command, .option, .control, .shift, .function]
        #expect(all.settingsText == "ctrl+opt+shift+cmd+fn")
        #expect(all.symbols == ["⌃", "⌥", "⇧", "⌘", "fn"])
        #expect(ModifierSet(settingsText: all.settingsText) == all)
        #expect(ModifierSet([.command, .shift]).symbols == ["⇧", "⌘"])
    }

    @Test("empty, unknown or dangling modifier parts are rejected")
    func modifierRejections() {
        #expect(ModifierSet(settingsText: "") == nil)
        #expect(ModifierSet(settingsText: "  ") == nil)
        #expect(ModifierSet(settingsText: "hyper") == nil)
        #expect(ModifierSet(settingsText: "opt+") == nil)
        #expect(ModifierSet(settingsText: "opt+meta") == nil)
    }

    @Test("every named key round-trips through its settings spelling, in any case")
    func namedKeyRoundTrip() {
        for key in NamedKey.allCases {
            let spec = KeySpec.named(key)
            #expect(KeySpec(settingsText: spec.settingsText) == spec)
            #expect(KeySpec(settingsText: spec.settingsText.uppercased()) == spec)
        }
        #expect(KeySpec(settingsText: "k")?.settingsText == "k")
    }

    @Test("key aliases map to their named keys")
    func keyAliases() {
        #expect(KeySpec(settingsText: "enter") == .named(.return))
        #expect(KeySpec(settingsText: "Esc") == .named(.escape))
        #expect(KeySpec(settingsText: "backspace") == .named(.delete))
        #expect(KeySpec(settingsText: "spacebar") == .named(.space))
        #expect(KeySpec(settingsText: "F20") == .named(.f20))
    }

    @Test("single characters are lowercased; empty and multi-character text is rejected")
    func characterKeys() {
        #expect(KeySpec(settingsText: "K") == .character("k"))
        #expect(KeySpec(settingsText: "ü") == .character("ü"))
        #expect(KeySpec(settingsText: "") == nil)
        #expect(KeySpec(settingsText: " ") == nil)
        #expect(KeySpec(settingsText: "kk") == nil)
        #expect(KeySpec(settingsText: "f21") == nil)
    }

    @Test("symbols show glyphs for named keys, F1–F20 and uppercase characters")
    func symbols() {
        #expect(KeySpec.named(.tab).symbol == "⇥")
        #expect(KeySpec.named(.space).symbol == "␣")
        #expect(KeySpec.named(.return).symbol == "↩")
        #expect(KeySpec.named(.escape).symbol == "⎋")
        #expect(KeySpec.named(.pageDown).symbol == "⇟")
        #expect(KeySpec.named(.f1).symbol == "F1")
        #expect(KeySpec.named(.f20).symbol == "F20")
        #expect(KeySpec.character("k").symbol == "K")
    }

    @Test("named keys match by key code, including keypad Enter for return")
    func namedMatching() {
        let returnKey = KeySpec.named(.return)
        #expect(returnKey.matches(KeyEvent(kind: .keyDown, keyCode: 0x24, modifiers: [])))
        #expect(returnKey.matches(KeyEvent(kind: .keyDown, keyCode: 0x4C, modifiers: [.function])))
        #expect(!returnKey.matches(KeyEvent(kind: .keyDown, keyCode: 0x30, modifiers: [], baseCharacters: "\r")))
    }

    @Test("characters match the unmodified character, so shift+cmd+1 matches 1 and not !")
    func characterMatching() {
        let shiftedOne = KeyEvent(kind: .keyDown, keyCode: 0x12, modifiers: [.shift, .command], characters: "!", baseCharacters: "1")
        #expect(KeySpec.character("1").matches(shiftedOne))
        #expect(!KeySpec.character("!").matches(shiftedOne))

        let shiftedK = KeyEvent(kind: .keyDown, keyCode: 0x28, modifiers: [.shift], characters: "K", baseCharacters: "k")
        #expect(KeySpec.character("k").matches(shiftedK))
        #expect(!KeySpec.character("k").matches(KeyEvent(kind: .keyDown, keyCode: 0x28, modifiers: [], characters: "k")))
        #expect(!KeySpec.character("k").matches(KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: [.command])))
    }
}
