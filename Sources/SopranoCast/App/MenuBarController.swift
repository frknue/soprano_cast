import AppKit
import OSLog
import SopranoCastCore

private let menuLog = Logger(subsystem: "com.soprano.cast", category: "menu-bar")

/// The status item and its menu. The icon follows `app.showMenuBarIcon` (removed while
/// false); the menu is rebuilt each time it opens, so the warning lines and the Launch at
/// Login checkmark are always current.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    /// Why some hotkeys don't work right now (shown in the menu).
    struct HotkeyProblems {
        var failures: [HotkeyFailure]
        /// The Hyper key could not be set up.
        var hyperKeyError: String?

        var count: Int { failures.count + (hyperKeyError == nil ? 0 : 1) }
    }

    private let controller: LauncherController
    private let settings: SettingsCenter
    private let hotkeyProblems: @MainActor () -> HotkeyProblems
    private let openPermissions: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private var statusItem: NSStatusItem?

    init(
        controller: LauncherController,
        settings: SettingsCenter = .shared,
        hotkeyProblems: @escaping @MainActor () -> HotkeyProblems,
        openPermissions: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.settings = settings
        self.hotkeyProblems = hotkeyProblems
        self.openPermissions = openPermissions
        self.openSettings = openSettings
        super.init()
        apply()
    }

    /// Re-applies `app.showMenuBarIcon`.
    func apply() {
        guard settings.settings.app.showMenuBarIcon else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = CastGlyph.templateImage()
        item.button?.toolTip = "Soprano Cast"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = settings.settings
        menu.removeAllItems()

        let open = item("Open Soprano Cast", action: #selector(openLauncher))
        if let hotkey = current.launcher.hotkey {
            if let equivalent = Self.keyEquivalent(for: hotkey, hyperIncludesShift: current.hyperKey.includeShift) {
                open.keyEquivalent = equivalent.key
                open.keyEquivalentModifierMask = equivalent.modifiers
            } else {
                open.title = "Open Soprano Cast  \(KeyboardLayout.keycaps(for: hotkey).joined())"
            }
        }
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(openSettingsWindow), key: ","))

        let issues = settings.issues
        if !issues.isEmpty {
            let count = issues.count
            let warning = disabledItem("settings.json: \(count) warning\(count == 1 ? "" : "s")")
            warning.toolTip = issues.map { issue in
                issue.line.map { "line \($0): \(issue.message)" } ?? issue.message
            }.joined(separator: "\n")
            menu.addItem(warning)
        }

        let problems = hotkeyProblems()
        if problems.count > 0 {
            let count = problems.count
            let attention = disabledItem("\(count) hotkey\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention")
            attention.toolTip = problemLines(problems).joined(separator: "\n")
            menu.addItem(attention)
        }

        menu.addItem(item("Permissions…", action: #selector(showPermissions)))
        menu.addItem(.separator())
        let launchAtLogin = item("Launch at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = current.app.startAtLogin ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(item("About Soprano Cast", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Soprano Cast", action: #selector(quit), key: "q"))
    }

    /// The menu's key equivalent for a combo hotkey (Hyper expanded; a physical key as the
    /// character it types on the current layout); nil for modifier gestures, fn combos and
    /// physical keys the layout types nothing with, which the title shows as keycaps instead.
    static func keyEquivalent(for spec: HotkeySpec, hyperIncludesShift: Bool) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard case .combo(let combo) = spec else { return nil }
        let modifierSet = combo.effectiveModifiers(hyperIncludesShift: hyperIncludesShift)
        guard !modifierSet.contains(.function) else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        if modifierSet.contains(.control) { modifiers.insert(.control) }
        if modifierSet.contains(.option) { modifiers.insert(.option) }
        if modifierSet.contains(.shift) { modifiers.insert(.shift) }
        if modifierSet.contains(.command) { modifiers.insert(.command) }
        let key: String
        switch combo.key {
        case .character(let character):
            key = String(character).lowercased()
        case .physical(let code):
            // The character the key types on the current layout; none → no key equivalent.
            guard let character = KeyboardLayout.character(for: code) else { return nil }
            key = String(character).lowercased()
        case .named(let named):
            key = keyEquivalentCharacter(for: named)
        }
        return (key, modifiers)
    }

    private static func keyEquivalentCharacter(for key: NamedKey) -> String {
        let scalar: Int = switch key {
        case .tab: NSTabCharacter
        case .space: 0x20
        case .return: NSCarriageReturnCharacter
        case .escape: 0x1B
        case .delete: NSBackspaceCharacter
        case .forwardDelete: NSDeleteFunctionKey
        case .left: NSLeftArrowFunctionKey
        case .right: NSRightArrowFunctionKey
        case .up: NSUpArrowFunctionKey
        case .down: NSDownArrowFunctionKey
        case .home: NSHomeFunctionKey
        case .end: NSEndFunctionKey
        case .pageUp: NSPageUpFunctionKey
        case .pageDown: NSPageDownFunctionKey
        case .f1: NSF1FunctionKey
        case .f2: NSF2FunctionKey
        case .f3: NSF3FunctionKey
        case .f4: NSF4FunctionKey
        case .f5: NSF5FunctionKey
        case .f6: NSF6FunctionKey
        case .f7: NSF7FunctionKey
        case .f8: NSF8FunctionKey
        case .f9: NSF9FunctionKey
        case .f10: NSF10FunctionKey
        case .f11: NSF11FunctionKey
        case .f12: NSF12FunctionKey
        case .f13: NSF13FunctionKey
        case .f14: NSF14FunctionKey
        case .f15: NSF15FunctionKey
        case .f16: NSF16FunctionKey
        case .f17: NSF17FunctionKey
        case .f18: NSF18FunctionKey
        case .f19: NSF19FunctionKey
        case .f20: NSF20FunctionKey
        }
        return UnicodeScalar(UInt32(scalar)).map { String(Character($0)) } ?? ""
    }

    /// "⌘⇧K Google Chrome: used by macOS" per failure, then the Hyper key's error.
    private func problemLines(_ problems: HotkeyProblems) -> [String] {
        let titles = Dictionary(controller.allItems.map { ($0.id, $0.title) }) { first, _ in first }
        var lines = problems.failures.map { failure in
            let target = switch failure.binding.target {
            case .launcher: "Soprano Cast"
            case .item(let id): titles[id] ?? id.rawValue
            }
            return "\(KeyboardLayout.keycaps(for: failure.binding.spec).joined()) \(target): \(failure.reason)"
        }
        if let hyperKeyError = problems.hyperKeyError {
            lines.append("Hyper key: \(hyperKeyError)")
        }
        return lines
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openLauncher() {
        controller.show()
    }

    @objc private func openSettingsWindow() {
        openSettings()
    }

    @objc private func showPermissions() {
        openPermissions()
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = !settings.settings.app.startAtLogin
        do {
            try settings.edit(.set(enabled, ["app", "startAtLogin"]))
        } catch {
            menuLog.error("Could not write app.startAtLogin: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Soprano Cast",
            .applicationVersion: AppVersion.current,
            .version: "",
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
