import AppKit
import SopranoCastCore

/// Advanced (Raycast's): where and how the launcher opens and the Hyper key.
@MainActor
final class AdvancedSettingsPane: NSView, SettingsPane {
    weak var host: SettingsHost?
    private let scroll = SettingsScrollColumn()

    static let screens: [(LauncherScreen, String)] = [
        (.withMouse, "Screen containing mouse"),
        (.withActiveWindow, "Screen with active window"),
        (.primary, "Primary screen"),
    ]
    static let popToRootChoices: [(Int, String)] = [
        (0, "Immediately"),
        (30, "After 30 seconds"),
        (90, "After 90 seconds"),
        (180, "After 3 minutes"),
        (300, "After 5 minutes"),
        (600, "After 10 minutes"),
        (3600, "After 1 hour"),
    ]
    static let navigations: [(NavigationBindings, String)] = [
        (.emacs, "macOS standard (⌃N, ⌃P)"),
        (.vim, "Vim (⌃J, ⌃K)"),
        (.both, "Both"),
    ]
    static let triggers: [(HyperTrigger?, String)] = [
        (nil, "None"),
        (.capsLock, "Caps Lock"),
        (.rightCommand, "Right Command"),
        (.rightOption, "Right Option"),
        (.rightControl, "Right Control"),
        (.rightShift, "Right Shift"),
        (.f18, "F18"),
    ]
    static let quickPresses: [(HyperQuickPress, String)] = [
        (.nothing, "Nothing"),
        (.toggleCapsLock, "Toggle Caps Lock"),
        (.escape, "Escape"),
    ]

    /// The pop-to-root values behind the pop-up's items (a custom value is appended).
    private var popToRootValues: [Int] = []

    init() {
        super.init(frame: .zero)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func reload() {
        guard let host else { return }
        let chrome = SettingsChrome(theme: host.theme)
        scroll.setContent([
            chrome.tabHeader(title: "Advanced", subtitle: "Where Soprano Cast opens, how it navigates, and the Hyper key."),
            launcherCard(chrome, host.settings.launcher),
            hyperKeyCard(chrome, host.settings.hyperKey),
        ])
    }

    private func launcherCard(_ chrome: SettingsChrome, _ launcher: LauncherSettings) -> NSView {
        let (section, body) = chrome.sectionCard(title: "launcher")
        var choices = Self.popToRootChoices
        if !choices.contains(where: { $0.0 == launcher.popToRootSeconds }) {
            choices.append((launcher.popToRootSeconds, "After \(launcher.popToRootSeconds) seconds"))
        }
        popToRootValues = choices.map(\.0)
        chrome.addRows([
            chrome.row(
                label: "Show Soprano Cast on",
                control: chrome.popup(
                    titles: Self.screens.map(\.1),
                    selected: Self.screens.firstIndex { $0.0 == launcher.screen },
                    target: self,
                    action: #selector(screenChanged(_:))
                )
            ),
            chrome.row(
                label: "Pop to Root Search",
                control: chrome.popup(
                    titles: choices.map(\.1),
                    selected: choices.firstIndex { $0.0 == launcher.popToRootSeconds },
                    target: self,
                    action: #selector(popToRootChanged(_:))
                ),
                toolTip: "Reopening Soprano Cast later than this starts a new search."
            ),
            chrome.row(
                label: "Navigation bindings",
                control: chrome.popup(
                    titles: Self.navigations.map(\.1),
                    selected: Self.navigations.firstIndex { $0.0 == launcher.navigation },
                    target: self,
                    action: #selector(navigationChanged(_:))
                ),
                toolTip: "Extra keys that move through the list besides ↑ and ↓."
            ),
            chrome.row(
                label: "Close when another app is clicked",
                control: chrome.checkbox(
                    isOn: launcher.closeOnFocusLoss,
                    accessibilityLabel: "Close when another app is clicked",
                    target: self,
                    action: #selector(closeOnFocusLossChanged(_:))
                )
            ),
        ], to: body)
        return section
    }

    private func hyperKeyCard(_ chrome: SettingsChrome, _ hyperKey: HyperKeySettings) -> NSView {
        let (section, body) = chrome.sectionCard(
            title: "hyper key",
            subtitle: "Turns one key into ⌃⌥⇧⌘ (✦) for hotkeys. Needs Accessibility."
        )
        let quickPress = chrome.popup(
            titles: Self.quickPresses.map(\.1),
            selected: Self.quickPresses.firstIndex { $0.0 == hyperKey.quickPress },
            target: self,
            action: #selector(quickPressChanged(_:))
        )
        quickPress.isEnabled = hyperKey.trigger == .capsLock
        chrome.addRows([
            chrome.row(
                label: "Hyper key",
                control: chrome.popup(
                    titles: Self.triggers.map(\.1),
                    selected: Self.triggers.firstIndex { $0.0 == hyperKey.trigger },
                    target: self,
                    action: #selector(triggerChanged(_:))
                )
            ),
            chrome.row(
                label: "Include ⇧ in ✦",
                control: chrome.checkbox(
                    isOn: hyperKey.includeShift,
                    accessibilityLabel: "Include Shift in the Hyper key",
                    target: self,
                    action: #selector(includeShiftChanged(_:))
                ),
                toolTip: "Off: the Hyper key presses ⌃⌥⌘ only."
            ),
            chrome.row(
                label: "Quick press",
                control: quickPress,
                toolTip: "What tapping Caps Lock alone does (Caps Lock trigger only)."
            ),
        ], to: body)
        return section
    }

    // MARK: - Actions

    @objc private func screenChanged(_ sender: NSPopUpButton) {
        guard Self.screens.indices.contains(sender.indexOfSelectedItem) else { return }
        host?.apply([.set(Self.screens[sender.indexOfSelectedItem].0.rawValue, ["launcher", "screen"])])
    }

    @objc private func popToRootChanged(_ sender: NSPopUpButton) {
        guard popToRootValues.indices.contains(sender.indexOfSelectedItem) else { return }
        host?.apply([.set(popToRootValues[sender.indexOfSelectedItem], ["launcher", "popToRootSeconds"])])
    }

    @objc private func navigationChanged(_ sender: NSPopUpButton) {
        guard Self.navigations.indices.contains(sender.indexOfSelectedItem) else { return }
        host?.apply([.set(Self.navigations[sender.indexOfSelectedItem].0.rawValue, ["launcher", "navigation"])])
    }

    @objc private func closeOnFocusLossChanged(_ sender: NSButton) {
        host?.apply([.set(sender.state == .on, ["launcher", "closeOnFocusLoss"])])
    }

    @objc private func triggerChanged(_ sender: NSPopUpButton) {
        guard Self.triggers.indices.contains(sender.indexOfSelectedItem) else { return }
        setHyperTrigger(Self.triggers[sender.indexOfSelectedItem].0)
    }

    /// Writes the trigger (`null` for none); a quick press needs the Caps Lock trigger, so
    /// any other trigger resets it to nothing (the resolver would warn and ignore it).
    func setHyperTrigger(_ trigger: HyperTrigger?) {
        guard let host else { return }
        let value: Any = trigger?.rawValue ?? NSNull()
        var edits: [SettingsEdit] = [.set(value, ["hyperKey", "trigger"])]
        if trigger != .capsLock, host.settings.hyperKey.quickPress != .nothing {
            edits.append(.set(HyperQuickPress.nothing.rawValue, ["hyperKey", "quickPress"]))
        }
        host.apply(edits)
    }

    @objc private func includeShiftChanged(_ sender: NSButton) {
        host?.apply([.set(sender.state == .on, ["hyperKey", "includeShift"])])
    }

    @objc private func quickPressChanged(_ sender: NSPopUpButton) {
        guard Self.quickPresses.indices.contains(sender.indexOfSelectedItem) else { return }
        host?.apply([.set(Self.quickPresses[sender.indexOfSelectedItem].0.rawValue, ["hyperKey", "quickPress"])])
    }
}
