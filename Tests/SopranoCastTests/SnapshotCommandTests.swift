import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct SnapshotCommandTests {
    private typealias Command = SnapshotCommand

    private func parse(_ arguments: [String]) throws -> Command.Options {
        try Command.parse(["--out", "/tmp/soprano-cast-snapshot.png"] + arguments)
    }

    private func render(_ arguments: [String]) throws -> SnapshotReport {
        try Command.render(try parse(arguments)).report
    }

    @Test("only --out is required; everything else has a default")
    func defaults() throws {
        let options = try parse([])
        #expect(options.out.path == "/tmp/soprano-cast-snapshot.png")
        #expect(options.query == nil && options.keys.isEmpty)
        #expect(options.settings == nil && options.theme == nil && options.report == nil)
        #expect(options.screenSize == CGSize(width: 1512, height: 982))
    }

    @Test("every option parses into its field")
    func everyOption() throws {
        let options = try parse([
            "--query", "chrome", "--keys", "down  cmd+k", "--settings", "/tmp/cast.jsonc",
            "--screen", "1920x1200", "--theme", "nord", "--report", "/tmp/report.json",
        ])
        #expect(options.query == "chrome")
        #expect(options.keys == [.press(.named(.down), []), .press(.character("k"), .command)])
        #expect(options.settings?.path == "/tmp/cast.jsonc")
        #expect(options.screenSize == CGSize(width: 1920, height: 1200))
        #expect(options.theme == "nord")
        #expect(options.report?.path == "/tmp/report.json")
    }

    @Test("key tokens: named keys and aliases, modifiers, shifted characters, recordings, waits")
    func keyTokens() throws {
        #expect(try Command.keyToken("return") == .press(.named(.return), []))
        #expect(try Command.keyToken("enter") == .press(.named(.return), []))
        #expect(try Command.keyToken("esc") == .press(.named(.escape), []))
        #expect(try Command.keyToken("space") == .press(.named(.space), []))
        #expect(try Command.keyToken("shift+tab") == .press(.named(.tab), .shift))
        #expect(try Command.keyToken("cmd+esc") == .press(.named(.escape), .command))
        #expect(try Command.keyToken("opt+return") == .press(.named(.return), .option))
        #expect(try Command.keyToken("ctrl+n") == .press(.character("n"), .control))
        #expect(try Command.keyToken("cmd+K") == .press(.character("k"), .command))
        #expect(try Command.keyToken("shift+cmd+,") == .press(.character(","), [.shift, .command]))
        #expect(try Command.keyToken("cmd++") == .press(.character("="), [.shift, .command]))
        #expect(try Command.keyToken("a") == .press(.character("a"), []))
        #expect(try Command.keyToken("A") == .press(.character("a"), .shift))
        #expect(try Command.keyToken("!") == .press(.character("1"), .shift))
        let commandOne = try #require(HotkeySpec(settingsText: "cmd+1"))
        #expect(try Command.keyToken("rec:cmd+1") == .record(commandOne))
        #expect(try Command.keyToken("cmd+key:'") == .press(.physical(0x27), .command))
        #expect(try Command.keyToken("key:0x27") == .press(.physical(0x27), []))
        #expect(try Command.keyToken("rec:cmd+key:z") == .record(.combo(HotkeyCombo(modifiers: .command, key: .physical(0x06)))))
        #expect(try Command.keyToken("rec:double:cmd") == .record(.doubleTap(SidedModifier(.command))))
        #expect(try Command.keyToken("wait") == .wait(milliseconds: 2000))
        #expect(try Command.keyToken("wait:150") == .wait(milliseconds: 150))
    }

    @Test("bad input is rejected with the matching error")
    func errors() {
        #expect(throws: Command.OptionError.missingOut) { try Command.parse(["--query", "x"]) }
        #expect(throws: Command.OptionError.missingValue("--keys")) { try parse(["--keys"]) }
        #expect(throws: Command.OptionError.unknownOption("--scenario")) { try parse(["--scenario", "x"]) }
        #expect(throws: Command.OptionError.badScreen("1512")) { try parse(["--screen", "1512"]) }
        #expect(throws: Command.OptionError.badScreen("640x480")) { try parse(["--screen", "640x480"]) }
        #expect(throws: Command.OptionError.unknownKeyToken("ö")) { try parse(["--keys", "down ö"]) }
        #expect(throws: Command.OptionError.unknownKeyToken("super+k")) { try parse(["--keys", "super+k"]) }
        #expect(throws: Command.OptionError.unknownKeyToken("cmd+nope")) { try parse(["--keys", "cmd+nope"]) }
        #expect(throws: Command.OptionError.badRecording("rec:k")) { try parse(["--keys", "rec:k"]) }
        #expect(throws: Command.OptionError.badWait("wait:-1")) { try parse(["--keys", "wait:-1"]) }
        #expect(throws: Command.OptionError.badWait("wait:soon")) { try parse(["--keys", "wait:soon"]) }
    }

    @Test("a combo replays modifier down, keyDown with characters, modifier up")
    func comboEvents() throws {
        var replay = Command.KeyReplay(hyperIncludesShift: true)
        let events = replay.events(for: try Command.keyToken("shift+cmd+,"))
        #expect(events.map { $0.kind } == [.flagsChanged, .flagsChanged, .keyDown, .flagsChanged, .flagsChanged])
        #expect(events[1].modifiers == [.shift, .command])
        #expect(events[2].keyCode == 0x2B)
        #expect(events[2].characters == "<")
        #expect(events[2].baseCharacters == ",")
        #expect(events[4].modifiers.isEmpty && events[4].sides.isEmpty)
        let increasing = zip(events, events.dropFirst()).allSatisfy { pair in pair.0.timestamp < pair.1.timestamp }
        #expect(increasing)
    }

    @Test("recording replays: hyper holds all four modifiers, a double tap fits the double-tap window, a physical key sends its code")
    func recordingEvents() throws {
        var replay = Command.KeyReplay(hyperIncludesShift: true)
        let hyper = replay.events(for: try Command.keyToken("rec:hyper+k"))
        #expect(hyper.first { $0.kind == .keyDown }?.modifiers == .hyper)

        let double = replay.events(for: try Command.keyToken("rec:double:rcmd"))
        #expect(double.count == 4)
        #expect(double.allSatisfy { $0.kind == .flagsChanged && $0.keyCode == 0x36 })
        #expect(double[0].sides == .rightCommand && double[1].sides.isEmpty)
        #expect(double[2].timestamp - double[1].timestamp < HotkeyRecorder.doubleTapWindow)

        let both = replay.events(for: try Command.keyToken("rec:both:shift"))
        #expect(both[1].sides == [.leftShift, .rightShift])

        let physical = replay.events(for: try Command.keyToken("rec:cmd+key:'"))
        let keyDown = try #require(physical.first { $0.kind == .keyDown })
        #expect(keyDown.keyCode == 0x27)
        #expect(keyDown.baseCharacters == "'")
        #expect(keyDown.modifiers == .command)
    }

    @Test("the default snapshot is the screen at 2x with suggestions listed")
    func renderDefault() throws {
        let result = try Command.render(try parse([]))
        #expect(result.image.width == 1512 * 2)
        #expect(result.image.height == 982 * 2)
        #expect(!result.report.rows.isEmpty)
        #expect(result.report.query == "")
        #expect(result.report.overlay == "none")
        #expect(result.report.runs.isEmpty && result.report.edits.isEmpty)
    }

    @Test("the settings-window options parse; each mode rejects the other's options")
    func settingsWindowOptions() throws {
        let options = try parse([
            "--settings-window", "extensions", "--select", "group:quicklinks", "--filter", "git", "--record", "launcher",
        ])
        #expect(options.settingsWindow == .extensions)
        #expect(options.select == "group:quicklinks")
        #expect(options.filter == "git")
        #expect(options.record == "launcher")
        #expect(throws: Command.OptionError.badSettingsTab("misc")) { try parse(["--settings-window", "misc"]) }
        #expect(throws: Command.OptionError.needsSettingsWindow("--select")) { try parse(["--select", "group:system"]) }
        #expect(throws: Command.OptionError.launcherOnly("--query")) { try parse(["--settings-window", "general", "--query", "x"]) }
        #expect(throws: Command.OptionError.launcherOnly("--screen")) { try parse(["--settings-window", "general", "--screen", "1920x1200"]) }
    }

    @Test("the settings window renders at 2x; a filter lists only matching rows; a recording saves after wait")
    func renderSettingsWindow() throws {
        let result = try Command.render(try parse(["--settings-window", "extensions", "--filter", "left half"]))
        #expect(result.image.width == Int(SettingsWindowController.contentSize.width) * 2)
        #expect(result.report.rows == ["group:windowManagement", "window:leftHalf"])
        #expect(result.report.query == "left half")

        let recorded = try render(["--settings-window", "extensions", "--record", "app:com.apple.mail", "--keys", "rec:cmd+2 wait"])
        #expect(recorded.overlay == "none")
        #expect(recorded.edits == ["set hotkeys.app:com.apple.mail = \"cmd+key:2\""])
        #expect(throws: FixtureError.self) { try render(["--settings-window", "extensions", "--select", "app:com.example.none"]) }
    }

    @Test("a query ranks and selects Google Chrome first")
    func renderQuery() throws {
        let report = try render(["--query", "chrome"])
        #expect(report.query == "chrome")
        #expect(report.rows.first == "app:com.google.Chrome")
        #expect(report.selected == "app:com.google.Chrome")
    }

    @Test("return after a query runs the selection")
    func renderReturn() throws {
        let report = try render(["--query", "chrome", "--keys", "return"])
        #expect(report.runs == ["run app:com.google.Chrome"])
    }

    @Test("cmd+k opens the action panel")
    func renderActionPanel() throws {
        let report = try render(["--keys", "cmd+k"])
        #expect(report.overlay == "actionPanel")
    }

    @Test("character keys the launcher doesn't use type into the search field")
    func renderTyping() throws {
        let report = try render(["--keys", "c h r o m x delete e"])
        #expect(report.query == "chrome")
        #expect(report.selected == "app:com.google.Chrome")
    }

    @Test("a recorded hotkey saves only after wait lets the countdown run")
    func renderRecorder() throws {
        let keys = "shift+cmd+, return rec:cmd+2"
        let recording = try render(["--query", "chrome", "--keys", keys])
        #expect(recording.overlay == "recorder")
        #expect(recording.edits.isEmpty)

        let saved = try render(["--query", "chrome", "--keys", keys + " wait"])
        #expect(saved.edits == ["set hotkeys.app:com.google.Chrome = \"cmd+key:2\""])
    }

    @Test("the report writes missing values as null")
    func reportJSON() throws {
        let report = SnapshotReport(
            query: "", rows: [], selected: nil, overlay: "none", runs: ["run app:com.apple.mail"], edits: [], footerToast: nil
        )
        let text = String(decoding: try report.jsonData(), as: UTF8.self)
        #expect(text.contains("\"selected\" : null"))
        #expect(text.contains("\"footerToast\" : null"))
        #expect(text.contains("\"runs\" : [\n    \"run app:com.apple.mail\"\n  ]"))
    }
}
