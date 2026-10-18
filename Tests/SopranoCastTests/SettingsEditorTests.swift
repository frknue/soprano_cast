import AppKit
import Testing
@testable import SopranoCastCore

struct SettingsEditorTests {
    private let document = """
    // my settings
    {
      "theme": "nord", // favorite
      "launcher": {
        /* keep me */
        "screen": "primary"
      },
      "hotkeys": {
        "window:leftHalf": "ctrl+opt+left",
        "app:com.google.Chrome": "cmd+1" // browser
      }
    }
    """
    private let chrome = ItemID(rawValue: "app:com.google.Chrome")
    private let leftHalf = ItemID(rawValue: "window:leftHalf")

    private func resolve(_ text: String) -> SettingsResolution {
        SettingsResolver.resolve(text: text, knownThemeIDs: ["nord"])
    }

    @Test("replacing a value keeps comments and the other keys")
    func replaceKeepsComments() throws {
        let edited = try SettingsEditor.setting("withActiveWindow", at: ["launcher", "screen"], in: document)
        #expect(edited.contains("// my settings"))
        #expect(edited.contains("// favorite"))
        #expect(edited.contains("/* keep me */"))
        #expect(edited.contains("// browser"))
        let settings = resolve(edited).settings
        #expect(settings?.launcher.screen == .withActiveWindow)
        #expect(settings?.theme == "nord")
        #expect(settings?.hotkeys.count == 2)
    }

    @Test("setting new and nested keys creates their objects")
    func createsNestedPath() throws {
        var edited = try SettingsEditor.setting("gc", at: ["aliases", "app:com.google.Chrome"], in: document)
        edited = try SettingsEditor.setting("cmd+2", at: ["hotkeys", "app:com.apple.Safari"], in: edited)
        edited = try SettingsEditor.setting(NSNull(), at: ["launcher", "hotkey"], in: edited)
        edited = try SettingsEditor.setting(8, at: ["windowManagement", "gap"], in: edited)
        edited = try SettingsEditor.setting(["app:com.google.Chrome"], at: ["favorites"], in: edited)
        let resolution = resolve(edited)
        #expect(resolution.issues.isEmpty)
        let settings = resolution.settings ?? CastSettings()
        #expect(settings.aliases == [chrome: "gc"])
        #expect(settings.hotkeys[ItemID(rawValue: "app:com.apple.Safari")] == .combo(HotkeyCombo(modifiers: .command, key: .character("2"))))
        #expect(settings.launcher.hotkey == nil)
        #expect(settings.launcher.screen == .primary)
        #expect(settings.windowManagement.gap == 8)
        #expect(settings.favorites == [chrome])
        #expect(edited.contains("/* keep me */"))
    }

    @Test("removing a key keeps the comments and the other keys")
    func removesKeepingComments() throws {
        let edited = try SettingsEditor.removing(at: ["hotkeys", "window:leftHalf"], in: document)
        #expect(edited.contains("// my settings"))
        #expect(edited.contains("// browser"))
        #expect(edited.contains("/* keep me */"))
        let resolution = resolve(edited)
        #expect(resolution.issues.isEmpty)
        #expect(resolution.settings?.hotkeys.keys.sorted() == [chrome])
        #expect(resolution.settings?.hotkeys[leftHalf] == nil)
    }

    @Test("removing an absent key leaves the text unchanged")
    func removingAbsentKey() throws {
        #expect(try SettingsEditor.removing(at: ["aliases", "app:x"], in: document) == document)
    }

    @Test("an unreadable document throws an edit error with its line")
    func parseErrorThrows() {
        do {
            _ = try SettingsEditor.setting(true, at: ["app", "startAtLogin"], in: "{\n\n  \"a\": nope\n}")
            Issue.record("expected an error")
        } catch let error as SettingsEditError {
            #expect(error.line == 3)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        do {
            _ = try SettingsEditor.removing(at: ["theme"], in: "{\n  \"theme\": \n}")
            Issue.record("expected an error")
        } catch let error as SettingsEditError {
            #expect(error.line == 3)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
