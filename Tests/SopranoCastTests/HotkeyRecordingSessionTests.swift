import AppKit
import Testing
@testable import SopranoCastCore

struct HotkeyRecordingSessionTests {
    private let chrome = ItemID(rawValue: "app:com.google.Chrome")
    private let mail = ItemID(rawValue: "app:com.apple.mail")
    private let commandTwo = HotkeySpec.combo(HotkeyCombo(modifiers: .command, key: .physical(0x13)))

    private func commandDown(at time: TimeInterval = 0) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: 0x37, modifiers: .command, sides: .leftCommand, timestamp: time)
    }

    private func two(at time: TimeInterval = 0.05) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: 0x13, modifiers: .command, sides: .leftCommand,
                 characters: "2", baseCharacters: "2", isRepeat: false, timestamp: time)
    }

    private func plain(_ keyCode: UInt16) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: keyCode, modifiers: [], sides: [],
                 characters: nil, baseCharacters: nil, isRepeat: false, timestamp: 0)
    }

    @Test("the session starts on the current hotkey and a hold replaces it with the held keycaps")
    func holdReplacesShownKeys() {
        var session = HotkeyRecordingSession(target: .item(chrome), current: commandTwo)
        #expect(session.keys == .spec(commandTwo))
        #expect(session.handle(commandDown()) { _ in nil } == .redraw)
        #expect(session.keys == .display(["L⌘"]))
        #expect(session.recorded == nil)
    }

    @Test("a free hotkey starts the countdown and commits as a save that takes nothing")
    func freeHotkeySaves() {
        var session = HotkeyRecordingSession(target: .item(chrome), current: nil)
        _ = session.handle(commandDown()) { _ in nil }
        #expect(session.handle(two()) { _ in nil } == .startCountdown)
        #expect(session.keys == .spec(commandTwo))
        #expect(session.commit { _ in nil } == .save(commandTwo, takingFrom: nil))
    }

    @Test("a hotkey another item holds saves by taking it from that item, which the card names")
    func heldHotkeyIsTaken() {
        var session = HotkeyRecordingSession(target: .item(chrome), current: nil)
        let owner: (HotkeySpec) -> HotkeyTarget? = { _ in .item(mail) }
        _ = session.handle(commandDown(), owner: owner)
        #expect(session.handle(two(), owner: owner) == .startCountdown)
        #expect(session.owner == .item(mail))
        #expect(session.commit(owner: owner) == .save(commandTwo, takingFrom: .item(mail)))
    }

    @Test("the launcher's own hotkey can't be taken: no countdown, and return does nothing")
    func launcherHotkeyStays() {
        var session = HotkeyRecordingSession(target: .item(chrome), current: nil)
        let owner: (HotkeySpec) -> HotkeyTarget? = { _ in .launcher }
        _ = session.handle(commandDown(), owner: owner)
        #expect(session.handle(two(), owner: owner) == .redraw)
        #expect(session.owner == .launcher)
        #expect(session.handle(plain(0x24), owner: owner) == HotkeyRecordingSession.Step.none)
    }

    @Test("delete clears, escape closes, and return with nothing recorded closes")
    func controlKeys() {
        var session = HotkeyRecordingSession(target: .launcher, current: commandTwo)
        #expect(session.handle(plain(0x33)) { _ in nil } == .clear)
        #expect(session.handle(plain(0x35)) { _ in nil } == .close)
        #expect(session.handle(plain(0x24)) { _ in nil } == .close)
    }
}
