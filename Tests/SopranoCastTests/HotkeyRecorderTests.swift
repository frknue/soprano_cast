import AppKit
import Testing
@testable import SopranoCastCore

struct HotkeyRecorderTests {
    private func flags(_ modifiers: ModifierSet, _ sides: ModifierSides, at time: TimeInterval = 0) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: modifiers, sides: sides, timestamp: time)
    }

    private func key(
        _ keyCode: UInt16, _ modifiers: ModifierSet = [], sides: ModifierSides = [],
        characters: String? = nil, base: String? = nil, isRepeat: Bool = false, at time: TimeInterval = 0
    ) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: keyCode, modifiers: modifiers, sides: sides,
                 characters: characters ?? base, baseCharacters: base, isRepeat: isRepeat, timestamp: time)
    }

    private func released(at time: TimeInterval) -> KeyEvent {
        flags([], [], at: time)
    }

    @Test("shift+cmd+1 shows pending keycaps, then records the digit's physical key")
    func shiftCommandDigit() {
        var recorder = HotkeyRecorder()
        #expect(recorder.handle(flags(.command, .leftCommand)) == .pending(display: ["L⌘"]))
        #expect(recorder.handle(flags([.command, .shift], [.leftCommand, .leftShift])) == .pending(display: ["L⇧", "L⌘"]))
        let combo = HotkeySpec.combo(HotkeyCombo(modifiers: [.command, .shift], key: .physical(0x12)))
        #expect(recorder.handle(key(0x12, [.command, .shift], sides: [.leftCommand, .leftShift], characters: "!", base: "1")) == .recorded(combo))
        #expect(recorder.handle(KeyEvent(kind: .keyUp, keyCode: 0x12, modifiers: [.command, .shift])) == .unchanged)
        #expect(recorder.handle(flags(.command, .leftCommand)) == .unchanged)
        #expect(recorder.handle(released(at: 0.2)) == .unchanged)
        #expect(recorder.recorded == combo)
    }

    @Test("plain Escape, Return and Delete control the recorder without recording")
    func controlKeys() {
        var recorder = HotkeyRecorder()
        #expect(recorder.handle(key(0x35)) == .cancelled)
        #expect(recorder.handle(key(0x24)) == .commit)
        #expect(recorder.handle(key(0x4C)) == .commit)
        #expect(recorder.handle(key(0x33)) == .cleared)
        #expect(recorder.handle(key(0x35, isRepeat: true)) == .unchanged)
        #expect(recorder.recorded == nil)
    }

    @Test("cmd+Escape records a combo instead of cancelling")
    func commandEscape() {
        var recorder = HotkeyRecorder()
        _ = recorder.handle(flags(.command, .leftCommand))
        let combo = HotkeySpec.combo(HotkeyCombo(modifiers: .command, key: .named(.escape)))
        #expect(recorder.handle(key(0x35, .command, sides: .leftCommand)) == .recorded(combo))
        #expect(recorder.recorded == combo)
    }

    @Test("an ordinary key without modifiers and auto-repeats change nothing")
    func ignoredKeys() {
        var recorder = HotkeyRecorder()
        #expect(recorder.handle(key(0x00, base: "a")) == .unchanged)
        #expect(recorder.handle(key(0x7A)) == .unchanged)
        #expect(recorder.handle(key(0x28, .command, base: "k", isRepeat: true)) == .unchanged)
        #expect(recorder.recorded == nil)
    }

    @Test("F13 alone records a combo without modifiers")
    func standaloneFunctionKey() {
        var recorder = HotkeyRecorder()
        #expect(recorder.handle(key(0x69)) == .recorded(.combo(HotkeyCombo(modifiers: [], key: .named(.f13)))))
    }

    @Test("all four Hyper modifiers record explicitly, never as hyper")
    func hyperModifiers() {
        var recorder = HotkeyRecorder()
        let update = recorder.handle(key(0x12, .hyper, characters: "!", base: "1"))
        #expect(update == .recorded(.combo(HotkeyCombo(modifiers: .hyper, usesHyper: false, key: .physical(0x12)))))
        #expect(recorder.recorded?.settingsText == "ctrl+opt+shift+cmd+key:1")
    }

    @Test("printable keys record by position, so cmd+ä on German is the ' key everywhere")
    func physicalKeys() {
        var recorder = HotkeyRecorder()
        let quote = HotkeySpec.combo(HotkeyCombo(modifiers: .command, key: .physical(0x27)))
        #expect(recorder.handle(key(0x27, .command, base: "ä")) == .recorded(quote))
        #expect(recorder.recorded?.settingsText == "cmd+key:'")
        #expect(recorder.handle(key(0x0A, .command, base: "^")) == .recorded(.combo(HotkeyCombo(modifiers: .command, key: .physical(0x0A)))))
        #expect(recorder.recorded?.settingsText == "cmd+key:§")
        #expect(recorder.handle(key(0x7B, [.control, .option])) == .recorded(.combo(HotkeyCombo(modifiers: [.control, .option], key: .named(.left)))))
    }

    @Test("tapping right cmd alone records a right-sided tap")
    func rightCommandTap() {
        var recorder = HotkeyRecorder()
        #expect(recorder.handle(flags(.command, .rightCommand)) == .pending(display: ["R⌘"]))
        let tap = HotkeySpec.modifierTap([SidedModifier(.command, side: .right)])
        #expect(recorder.handle(released(at: 0.1)) == .recorded(tap))
        #expect(recorder.recorded?.settingsText == "rcmd")
    }

    @Test("tapping cmd and opt together records both as one tap, released in any order")
    func multiModifierTap() {
        var recorder = HotkeyRecorder()
        _ = recorder.handle(flags(.command, .leftCommand))
        #expect(recorder.handle(flags([.command, .option], [.leftCommand, .leftOption])) == .pending(display: ["L⌥", "L⌘"]))
        #expect(recorder.handle(flags(.command, .leftCommand, at: 0.1)) == .pending(display: ["L⌘"]))
        let tap = HotkeySpec.modifierTap([SidedModifier(.command, side: .left), SidedModifier(.option, side: .left)])
        #expect(recorder.handle(released(at: 0.15)) == .recorded(tap))
    }

    @Test("the same modifier tapped again within the window records a double tap")
    func doubleTapInsideWindow() {
        var recorder = HotkeyRecorder()
        let left = SidedModifier(.command, side: .left)
        _ = recorder.handle(flags(.command, .leftCommand, at: 0))
        #expect(recorder.handle(released(at: 0.1)) == .recorded(.modifierTap([left])))
        _ = recorder.handle(flags(.command, .leftCommand, at: 0.1 + HotkeyRecorder.doubleTapWindow - 0.05))
        #expect(recorder.handle(released(at: 0.5)) == .recorded(.doubleTap(left)))
        #expect(recorder.recorded == .doubleTap(left))
    }

    @Test("a second tap after the window, on the other side or after a key records a single tap")
    func doubleTapOutsideWindow() {
        let left = SidedModifier(.command, side: .left)

        var late = HotkeyRecorder()
        _ = late.handle(flags(.command, .leftCommand, at: 0))
        _ = late.handle(released(at: 0.1))
        _ = late.handle(flags(.command, .leftCommand, at: 0.1 + HotkeyRecorder.doubleTapWindow + 0.05))
        #expect(late.handle(released(at: 0.6)) == .recorded(.modifierTap([left])))

        var otherSide = HotkeyRecorder()
        _ = otherSide.handle(flags(.command, .leftCommand, at: 0))
        _ = otherSide.handle(released(at: 0.1))
        _ = otherSide.handle(flags(.command, .rightCommand, at: 0.2))
        #expect(otherSide.handle(released(at: 0.3)) == .recorded(.modifierTap([SidedModifier(.command, side: .right)])))

        var keyBetween = HotkeyRecorder()
        _ = keyBetween.handle(flags(.command, .leftCommand, at: 0))
        _ = keyBetween.handle(released(at: 0.1))
        _ = keyBetween.handle(key(0x00, base: "a", at: 0.15))
        _ = keyBetween.handle(flags(.command, .leftCommand, at: 0.2))
        #expect(keyBetween.handle(released(at: 0.3)) == .recorded(.modifierTap([left])))
    }

    @Test("left and right cmd down together record both sides")
    func bothCommands() {
        var recorder = HotkeyRecorder()
        _ = recorder.handle(flags(.command, .leftCommand))
        #expect(recorder.handle(flags(.command, [.leftCommand, .rightCommand])) == .pending(display: ["L⌘", "R⌘"]))
        #expect(recorder.handle(flags(.command, .rightCommand, at: 0.2)) == .pending(display: ["R⌘"]))
        #expect(recorder.handle(released(at: 0.3)) == .recorded(.bothSides(.command)))
    }

    @Test("a key pressed during a modifier hold records the combo, not a tap")
    func keyDuringHold() {
        var recorder = HotkeyRecorder()
        _ = recorder.handle(flags(.command, .rightCommand))
        let combo = HotkeySpec.combo(HotkeyCombo(modifiers: .command, key: .physical(0x28)))
        #expect(recorder.handle(key(0x28, .command, sides: .rightCommand, base: "k")) == .recorded(combo))
        #expect(recorder.handle(released(at: 0.2)) == .unchanged)
        #expect(recorder.recorded == combo)
    }

    @Test("a later recording replaces the earlier one")
    func replacesRecording() {
        var recorder = HotkeyRecorder()
        _ = recorder.handle(key(0x12, .command, base: "1"))
        _ = recorder.handle(flags(.option, .rightOption))
        _ = recorder.handle(released(at: 0.1))
        #expect(recorder.recorded == .modifierTap([SidedModifier(.option, side: .right)]))
    }
}
