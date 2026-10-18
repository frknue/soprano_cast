import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct KeyEventConversionTests {
    private func cgEvent(_ keyCode: CGKeyCode, down: Bool = true, flags: UInt64 = 0) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
        event.flags = CGEventFlags(rawValue: flags)
        return event
    }

    @Test("a keyDown keeps its kind, key code and modifiers")
    func keyDown() throws {
        let flags = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        let event = try #require(KeyEventConversion.keyEvent(from: cgEvent(0x12, flags: flags), type: .keyDown))
        #expect(event.kind == .keyDown)
        #expect(event.keyCode == 0x12)
        #expect(event.modifiers == [.command, .shift])
        #expect(event.isRepeat == false)
    }

    @Test("a keyUp converts as keyUp")
    func keyUp() throws {
        let event = try #require(KeyEventConversion.keyEvent(from: cgEvent(0x00, down: false), type: .keyUp))
        #expect(event.kind == .keyUp)
        #expect(event.keyCode == 0x00)
        #expect(event.modifiers.isEmpty)
    }

    @Test("device-dependent bits give the physical sides")
    func sides() throws {
        let independent: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let device: UInt64 = 0x10 | 0x20 | 0x2000 | 0x02 | 0x04   // R⌘ L⌥ R⌃ L⇧ R⇧
        let flags = independent.rawValue | device
        let event = try #require(KeyEventConversion.keyEvent(from: cgEvent(0x37, flags: flags), type: .flagsChanged))
        #expect(event.sides == [.rightCommand, .leftOption, .rightControl, .leftShift, .rightShift])
        #expect(event.modifiers == [.command, .option, .control, .shift])
    }

    @Test("left command and left control map to their own sides")
    func leftSides() {
        let sides = KeyEventConversion.sides(from: CGEventFlags(rawValue: 0x08 | 0x01))
        #expect(sides == [.leftCommand, .leftControl])
    }

    @Test("fn on a letter key counts as the function modifier")
    func functionOnLetter() throws {
        let event = try #require(KeyEventConversion.keyEvent(
            from: cgEvent(0x00, flags: CGEventFlags.maskSecondaryFn.rawValue), type: .keyDown
        ))
        #expect(event.modifiers == [.function])
        #expect(event.sides == [.function])
    }

    @Test("arrow keys drop the fn flag macOS always sets on them")
    func functionOnArrow() throws {
        let flags = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        let event = try #require(KeyEventConversion.keyEvent(from: cgEvent(0x7B, flags: flags), type: .keyDown))
        #expect(event.modifiers == [.control, .option])
        #expect(!event.sides.contains(.function))
    }

    @Test("the fn key's own flagsChanged keeps the function modifier")
    func functionFlagsChanged() throws {
        let event = try #require(KeyEventConversion.keyEvent(
            from: cgEvent(0x3F, flags: CGEventFlags.maskSecondaryFn.rawValue), type: .flagsChanged
        ))
        #expect(event.modifiers == [.function])
    }

    @Test("autorepeat marks the event as a repeat")
    func repeatFlag() throws {
        let source = cgEvent(0x00)
        source.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let event = try #require(KeyEventConversion.keyEvent(from: source, type: .keyDown))
        #expect(event.isRepeat)
    }

    @Test("flagsChanged carries no characters")
    func flagsChangedCharacters() throws {
        let event = try #require(KeyEventConversion.keyEvent(
            from: cgEvent(0x38, flags: CGEventFlags.maskShift.rawValue | 0x02), type: .flagsChanged
        ))
        #expect(event.kind == .flagsChanged)
        #expect(event.characters == nil)
        #expect(event.baseCharacters == nil)
    }

    @Test("the timestamp is the event's nanoseconds in seconds")
    func timestamp() throws {
        let source = cgEvent(0x00)
        source.timestamp = 2_500_000_000
        let event = try #require(KeyEventConversion.keyEvent(from: source, type: .keyDown))
        #expect(event.timestamp == 2.5)
    }

    @Test("event types other than key events convert to nil")
    func otherTypes() {
        #expect(KeyEventConversion.keyEvent(from: cgEvent(0x00), type: .leftMouseDown) == nil)
    }

    @Test("an NSEvent keyDown converts with its sides and characters")
    func nsEventKeyDown() throws {
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        let nsEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 7, windowNumber: 0,
            context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: true, keyCode: 0x28
        ))
        let event = try #require(KeyEventConversion.keyEvent(from: nsEvent))
        #expect(event.kind == .keyDown)
        #expect(event.keyCode == 0x28)
        #expect(event.modifiers == [.command])
        #expect(event.sides == [.rightCommand])
        #expect(event.characters == "k")
        #expect(event.isRepeat)
        #expect(event.timestamp == 7)
    }
}
