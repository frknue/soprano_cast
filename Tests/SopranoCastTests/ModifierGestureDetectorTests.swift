import AppKit
import Testing
@testable import SopranoCastCore

struct ModifierGestureDetectorTests {
    private func spec(_ text: String) -> HotkeySpec {
        HotkeySpec(settingsText: text)!
    }

    private func flags(_ modifiers: ModifierSet, _ sides: ModifierSides, at time: TimeInterval) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: modifiers, sides: sides, timestamp: time)
    }

    private func released(at time: TimeInterval) -> KeyEvent {
        flags([], [], at: time)
    }

    private func keyDown(at time: TimeInterval) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: 0x28, modifiers: [], characters: "k", baseCharacters: "k", timestamp: time)
    }

    /// Presses `sides` at `start` and releases everything at `end`; returns what fired on release.
    private func tap(
        _ detector: inout ModifierGestureDetector, _ modifiers: ModifierSet, _ sides: ModifierSides,
        from start: TimeInterval, to end: TimeInterval
    ) -> [HotkeySpec] {
        let pressed = detector.handle(flags(modifiers, sides, at: start))
        #expect(pressed.isEmpty)
        return detector.handle(released(at: end))
    }

    @Test("a tap fires on the release of its modifier, not on the press")
    func tapFiresOnRelease() {
        var detector = ModifierGestureDetector(specs: [spec("rcmd")])
        #expect(detector.handle(flags(.command, .rightCommand, at: 0)).isEmpty)
        #expect(detector.handle(released(at: 0.2)) == [spec("rcmd")])
    }

    @Test("a hold longer than the maximum tap duration does not fire")
    func longHoldDoesNotFire() {
        var detector = ModifierGestureDetector(specs: [spec("rcmd")])
        #expect(tap(&detector, .command, .rightCommand, from: 0, to: ModifierGestureDetector.maxTapDuration - 0.01) == [spec("rcmd")])
        #expect(tap(&detector, .command, .rightCommand, from: 1, to: 1 + ModifierGestureDetector.maxTapDuration + 0.01).isEmpty)
    }

    @Test("a key pressed during the hold cancels the tap")
    func keyCancelsTap() {
        var detector = ModifierGestureDetector(specs: [spec("rcmd")])
        _ = detector.handle(flags(.command, .rightCommand, at: 0))
        #expect(detector.handle(keyDown(at: 0.05)).isEmpty)
        #expect(detector.handle(released(at: 0.1)).isEmpty)
        #expect(tap(&detector, .command, .rightCommand, from: 0.2, to: 0.3) == [spec("rcmd")])
    }

    @Test("a multi-modifier tap needs exactly its modifiers")
    func multiModifierTap() {
        var detector = ModifierGestureDetector(specs: [spec("cmd+opt")])
        _ = detector.handle(flags(.command, .leftCommand, at: 0))
        _ = detector.handle(flags([.command, .option], [.leftCommand, .rightOption], at: 0.05))
        _ = detector.handle(flags(.option, .rightOption, at: 0.1))
        #expect(detector.handle(released(at: 0.15)) == [spec("cmd+opt")])
        #expect(tap(&detector, .command, .leftCommand, from: 1, to: 1.1).isEmpty)
        #expect(tap(&detector, [.command, .option, .shift], [.leftCommand, .leftOption, .leftShift], from: 2, to: 2.1).isEmpty)
    }

    @Test("a double tap fires on the second tap only when it starts within the window")
    func doubleTapTiming() {
        let window = HotkeyRecorder.doubleTapWindow
        var detector = ModifierGestureDetector(specs: [spec("double:cmd")])
        #expect(tap(&detector, .command, .leftCommand, from: 0, to: 0.1).isEmpty)
        #expect(tap(&detector, .command, .leftCommand, from: 0.1 + window - 0.05, to: 0.5) == [spec("double:cmd")])
        // The pair is complete; the next tap starts a new one.
        #expect(tap(&detector, .command, .leftCommand, from: 0.6, to: 0.65).isEmpty)
        #expect(tap(&detector, .command, .leftCommand, from: 0.7, to: 0.75) == [spec("double:cmd")])

        var late = ModifierGestureDetector(specs: [spec("double:cmd")])
        #expect(tap(&late, .command, .leftCommand, from: 0, to: 0.1).isEmpty)
        #expect(tap(&late, .command, .leftCommand, from: 0.1 + window + 0.05, to: 0.6).isEmpty)
    }

    @Test("a key between the two taps cancels the double tap")
    func keyCancelsDoubleTap() {
        var detector = ModifierGestureDetector(specs: [spec("double:opt")])
        #expect(tap(&detector, .option, .leftOption, from: 0, to: 0.1).isEmpty)
        #expect(detector.handle(keyDown(at: 0.15)).isEmpty)
        #expect(tap(&detector, .option, .leftOption, from: 0.2, to: 0.3).isEmpty)
    }

    @Test("both sides fires once when the second side goes down, and that hold is no tap")
    func bothSidesFiresOnce() {
        var detector = ModifierGestureDetector(specs: [spec("both:cmd"), spec("cmd")])
        #expect(detector.handle(flags(.command, .leftCommand, at: 0)).isEmpty)
        #expect(detector.handle(flags(.command, [.leftCommand, .rightCommand], at: 0.05)) == [spec("both:cmd")])
        #expect(detector.handle(flags(.command, .rightCommand, at: 0.1)).isEmpty)
        #expect(detector.handle(flags(.command, [.leftCommand, .rightCommand], at: 0.15)).isEmpty)
        #expect(detector.handle(released(at: 0.2)).isEmpty)
    }

    @Test("both sides does not fire with another modifier held")
    func bothSidesNeedsOnlyThatModifier() {
        var detector = ModifierGestureDetector(specs: [spec("both:shift")])
        _ = detector.handle(flags(.command, .leftCommand, at: 0))
        _ = detector.handle(flags([.command, .shift], [.leftCommand, .leftShift], at: 0.05))
        #expect(detector.handle(flags([.command, .shift], [.leftCommand, .leftShift, .rightShift], at: 0.1)).isEmpty)
    }

    @Test("left and right taps match their side; any-side taps match either")
    func sides() {
        var detector = ModifierGestureDetector(specs: [spec("lcmd"), spec("rcmd"), spec("cmd")])
        #expect(tap(&detector, .command, .leftCommand, from: 0, to: 0.1) == [spec("lcmd"), spec("cmd")])
        #expect(tap(&detector, .command, .rightCommand, from: 1, to: 1.1) == [spec("rcmd"), spec("cmd")])
    }

    @Test("combo specs are never watched")
    func combosIgnored() {
        var detector = ModifierGestureDetector(specs: [spec("cmd+k"), spec("fn")])
        #expect(tap(&detector, .function, .function, from: 0, to: 0.1) == [spec("fn")])
        _ = detector.handle(flags(.command, .leftCommand, at: 1))
        #expect(detector.handle(KeyEvent(kind: .keyDown, keyCode: 0x28, modifiers: .command, baseCharacters: "k", timestamp: 1.05)).isEmpty)
    }
}
