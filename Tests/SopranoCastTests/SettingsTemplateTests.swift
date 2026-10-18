import AppKit
import Testing
@testable import SopranoCastCore

struct SettingsTemplateTests {
    @Test("the template resolves to exactly the defaults with no issues")
    func resolvesToDefaults() {
        let resolution = SettingsResolver.resolve(text: SettingsTemplate.text, knownThemeIDs: [])
        #expect(resolution.issues.isEmpty)
        #expect(resolution.settings == .defaults)
    }

    @Test("the template documents the allowed values of every choice")
    func documentsAllowedValues() {
        let text = SettingsTemplate.text
        let values = LauncherScreen.allCases.map { $0.rawValue } + NavigationBindings.allCases.map { $0.rawValue }
            + HyperTrigger.allCases.map { $0.rawValue } + HyperQuickPress.allCases.map { $0.rawValue }
            + HalvesBehavior.allCases.map { $0.rawValue }
        for value in values {
            #expect(text.contains("\"\(value)\""), "missing \(value)")
        }
    }

    @Test("the template names every item kind, every built-in command and every hotkey shape")
    func documentsIDsAndHotkeys() {
        let text = SettingsTemplate.text
        for kind in ItemKind.allCases where kind != .calculator {
            #expect(text.contains("\(kind.prefix):"), "missing \(kind.prefix)")
        }
        let commands = SystemCommand.allCases.map { $0.rawValue } + WindowCommand.allCases.map { $0.rawValue }
            + CastCommand.allCases.map { $0.rawValue }
        for command in commands {
            #expect(text.contains(command), "missing \(command)")
        }
        for example in ["\"cmd+shift+k\"", "\"hyper+1\"", "\"f13\"", "\"rcmd\"", "\"double:cmd\"", "\"both:cmd\"", "{argument name=", "{clipboard}"] {
            #expect(text.contains(example), "missing \(example)")
        }
    }

    @Test("editing the template keeps its comments and applies the new value")
    func editableTemplate() throws {
        var edited = try SettingsEditor.setting("cmd+1", at: ["hotkeys", "app:com.google.Chrome"], in: SettingsTemplate.text)
        edited = try SettingsEditor.setting("gc", at: ["aliases", "app:com.google.Chrome"], in: edited)
        #expect(edited.contains("// Soprano Cast settings."))
        let resolution = SettingsResolver.resolve(text: edited, knownThemeIDs: [])
        #expect(resolution.issues.isEmpty)
        let chrome = ItemID(rawValue: "app:com.google.Chrome")
        #expect(resolution.settings?.hotkeys == [chrome: .combo(HotkeyCombo(modifiers: .command, key: .character("1")))])
        #expect(resolution.settings?.aliases == [chrome: "gc"])
    }
}
