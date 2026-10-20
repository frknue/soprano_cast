import AppKit
import OSLog
import SopranoCastCore

private let appLog = Logger(subsystem: "com.soprano.cast", category: "app")

/// The composition root: settings → theme → app, script and settings pane catalogs, icons,
/// runners → hotkeys and Hyper key → launcher window and controller → sources started →
/// hotkey bindings → menu bar → login item → CLI server → settings and theme observers →
/// first-launch permissions.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the first launch asked macOS for Accessibility.
    private static let didRequestPermissionsKey = "didRequestPermissions"

    private var appCatalog: LiveAppCatalog?
    private var scripts: ScriptCatalog?
    private var settingsPanes: LiveSettingsPaneCatalog?
    private var hotkeys: HotkeyCenter?
    private var hyperKey: HyperKeyController?
    private var controller: LauncherController?
    private var menuBar: MenuBarController?
    private var cliServer: CLIServer?
    private var permissionsWindow: PermissionsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var accessibilityPoll: Timer?

    private var appliedStartAtLogin: Bool?
    private var appliedBindings: [HotkeyBinding]?
    private var appliedHyperKey: HyperKeySettings?
    private var hotkeyFailures: [HotkeyFailure] = []
    private var hyperKeyError: String?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.anotherInstanceIsRunning() else {
            NSApp.terminate(nil)
            return
        }
        _ = RetroFont.registerBundledFont()

        let settingsCenter = SettingsCenter.shared
        settingsCenter.start()
        ThemeCenter.shared.start()
        let settings = settingsCenter.settings

        let appCatalog = LiveAppCatalog(extraDirectories: settings.applicationDirectories)
        let scriptRunner = ScriptRunner()
        let scripts = ScriptCatalog(directories: settings.scriptDirectories, runner: scriptRunner)
        let settingsPanes = LiveSettingsPaneCatalog()
        let icons = LiveIconProvider(theme: { ThemeCenter.shared.theme })
        let runner = LiveItemRunner(
            windowManager: LiveWindowManager(),
            scripts: scripts,
            scriptRunner: scriptRunner,
            systemCommands: SystemCommandRunner(),
            settings: { SettingsCenter.shared.settings },
            castCommand: { [weak self] command in
                self?.perform(command) ?? .done(closeLauncher: true)
            }
        )
        let hotkeys = HotkeyCenter()
        let hyperKey = HyperKeyController()
        let controller = LauncherController(
            sources: [appCatalog, scripts, settingsPanes],
            icons: icons,
            runner: runner,
            presenter: LauncherWindow(),
            hotkeys: hotkeys,
            environment: Self.environment(store: AppStateStore())
        )
        self.appCatalog = appCatalog
        self.scripts = scripts
        self.settingsPanes = settingsPanes
        self.hotkeys = hotkeys
        self.hyperKey = hyperKey
        self.controller = controller
        controller.onItemsChange = { [weak self] in
            self?.settingsWindow?.itemsDidChange()
        }

        // The controller listens to its sources from init on, so start them only now.
        appCatalog.start()
        scripts.start()
        settingsPanes.start()

        hotkeys.onTrigger = { [weak controller] target in
            switch target {
            case .launcher: controller?.toggle()
            case .item(let id): controller?.runHotkey(itemID: id)
            }
        }
        applyHotkeys(force: true)

        menuBar = MenuBarController(
            controller: controller,
            hotkeyProblems: { [weak self] in
                MenuBarController.HotkeyProblems(
                    failures: self?.hotkeyFailures ?? [],
                    hyperKeyError: self?.hyperKeyError
                )
            },
            openPermissions: { [weak self] in
                self?.showPermissions()
            },
            openSettings: { [weak self] in
                self?.showSettings()
            }
        )
        applyLoginItem()

        let cliServer = CLIServer(controller: controller)
        cliServer.start()
        self.cliServer = cliServer

        settingsCenter.addObserver(self) { [weak self] in
            self?.settingsDidChange()
        }
        ThemeCenter.shared.addObserver(self) { [weak self] in
            self?.controller?.settingsDidChange()
            self?.settingsWindow?.themeDidChange()
        }

        onboardIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cliServer?.stop()
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
        hyperKey?.remove()
        appCatalog?.stop()
        scripts?.stop()
        settingsPanes?.stop()
        SettingsCenter.shared.stop()
    }

    /// Reopening from Spotlight or Finder opens or closes the launcher, like its hotkey.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.toggle()
        return false
    }

    // MARK: - Composition

    private static func environment(store: AppStateStore) -> LauncherEnvironment {
        LauncherEnvironment(
            settings: { SettingsCenter.shared.settings },
            editSettings: { try SettingsCenter.shared.edit($0) },
            theme: { ThemeCenter.shared.theme },
            now: { Date() },
            schedule: Self.schedule,
            screenFrame: { Self.visibleFrame(for: $0) },
            loadUsage: { store.loadUsage() },
            saveUsage: { store.saveUsage($0) },
            loadHistory: { store.loadHistory() },
            saveHistory: { store.saveHistory($0) }
        )
    }

    /// Runs `work` on the main actor after `milliseconds`; the returned closure cancels it.
    private static func schedule(_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> (() -> Void) {
        let scheduled = ScheduledWork(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            MainActor.assumeIsolated {
                scheduled.run()
            }
        }
        // Controllers cancel on the main thread.
        return { MainActor.assumeIsolated { scheduled.cancel() } }
    }

    /// The AppKit visible frame of the display `choice` picks: the one under the mouse, the
    /// one holding the frontmost app's frontmost window (the main display without one), or
    /// the primary display.
    private static func visibleFrame(for choice: LauncherScreen) -> CGRect {
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        let chosen: NSScreen? = switch choice {
        case .withMouse:
            screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        case .withActiveWindow:
            activeWindowFrame(primaryHeight: primary.frame.height).flatMap { Self.screen(sharingMostWith: $0, in: screens) }
        case .primary:
            primary
        }
        return (chosen ?? NSScreen.main ?? primary).visibleFrame
    }

    /// The AppKit frame of the frontmost app's frontmost on-screen normal window.
    private static func activeWindowFrame(primaryHeight: CGFloat) -> CGRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        // Front to back: the first normal-layer window of the app is its frontmost.
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  quartz.width > 0, quartz.height > 0
            else { continue }
            return Geometry.appKitRect(fromQuartz: quartz, primaryHeight: primaryHeight)
        }
        return nil
    }

    private static func screen(sharingMostWith rect: CGRect, in screens: [NSScreen]) -> NSScreen? {
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(rect)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (screen, area) }
        }
        return best?.screen
    }

    private static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != ownPID && !$0.isTerminated }
    }

    // MARK: - Cast commands

    /// The cast commands `LiveItemRunner` hands back (it opens the search engines itself).
    private func perform(_ command: CastCommand) -> RunOutcome {
        switch command {
        case .openSettings:
            showSettings()
            return .done(closeLauncher: true)
        case .reloadScripts:
            scripts?.reload()
            return .hud("Reloaded script directories")
        case .searchGoogle, .searchDuckDuckGo:
            // Never routed here: the runner opens the engine URL with the query.
            return .done(closeLauncher: false)
        case .quit:
            NSApp.terminate(nil)
            return .done(closeLauncher: true)
        }
    }

    // MARK: - Settings

    private func settingsDidChange() {
        let settings = SettingsCenter.shared.settings
        appCatalog?.setExtraDirectories(settings.applicationDirectories)
        scripts?.setDirectories(settings.scriptDirectories)
        controller?.settingsDidChange()
        applyHotkeys(force: false)
        menuBar?.apply()
        settingsWindow?.settingsDidChange()
        applyLoginItem()
    }

    private func applyLoginItem() {
        let enabled = SettingsCenter.shared.settings.app.startAtLogin
        guard enabled != appliedStartAtLogin else { return }
        appliedStartAtLogin = enabled
        LoginItem.sync(enabled: enabled)
    }

    // MARK: - Hotkeys

    /// Applies the Hyper key and registers every binding when they changed (or `force`).
    /// While something failed for want of Accessibility, polls every second and applies
    /// everything again once it is granted.
    private func applyHotkeys(force: Bool) {
        guard let hotkeys, let hyperKey else { return }
        let settings = SettingsCenter.shared.settings
        let bindings = settings.hotkeyBindings
        let hyperKeyChanged = settings.hyperKey != appliedHyperKey
        if force || hyperKeyChanged {
            appliedHyperKey = settings.hyperKey
            hyperKeyError = hyperKey.apply(settings.hyperKey)
            if let hyperKeyError {
                appLog.error("Hyper key: \(hyperKeyError, privacy: .public)")
            }
        }
        // Hyper combos register with the Hyper key's modifiers, so they follow it too.
        if force || hyperKeyChanged || bindings != appliedBindings {
            appliedBindings = bindings
            hotkeyFailures = hotkeys.setBindings(bindings, hyperKey: settings.hyperKey)
            for failure in hotkeyFailures {
                appLog.error("Hotkey \(failure.binding.spec.settingsText, privacy: .public): \(failure.reason, privacy: .public)")
            }
        }
        updateAccessibilityPoll()
    }

    private func updateAccessibilityPoll() {
        let waiting = (!hotkeyFailures.isEmpty || hyperKeyError != nil) && !Permissions.isAccessibilityTrusted
        if waiting, accessibilityPoll == nil {
            accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.accessibilityPollFired()
                }
            }
        } else if !waiting {
            accessibilityPoll?.invalidate()
            accessibilityPoll = nil
        }
    }

    private func accessibilityPollFired() {
        guard Permissions.isAccessibilityTrusted else { return }
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
        applyHotkeys(force: true)
        permissionsWindow?.refresh()
    }

    // MARK: - Permissions

    /// The first launch asks macOS for Accessibility once and opens the permissions window
    /// when it is missing. Later launches don't: app, quicklink and script hotkeys work
    /// without it, and the menu reports the hotkeys that need it.
    private func onboardIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didRequestPermissionsKey) else { return }
        defaults.set(true, forKey: Self.didRequestPermissionsKey)
        guard !Permissions.status.allGranted else { return }
        Permissions.requestAccessibility()
        showPermissions()
    }

    private func showPermissions() {
        let window = permissionsWindow ?? PermissionsWindowController(status: { Permissions.status })
        permissionsWindow = window
        NSApp.activate()
        window.showWindow(nil)
    }

    // MARK: - Settings window

    /// Opens the settings window, created on first use.
    private func showSettings() {
        guard let hotkeys, let controller else { return }
        let window = settingsWindow ?? makeSettingsWindow(hotkeys: hotkeys, controller: controller)
        settingsWindow = window
        window.present()
    }

    private func makeSettingsWindow(hotkeys: HotkeyCenter, controller: LauncherController) -> SettingsWindowController {
        let center = SettingsCenter.shared
        let environment = SettingsWindowEnvironment(
            settings: { center.settings },
            issues: { center.issues },
            settingsPath: center.displayPath,
            editSettings: { try center.edit($0) },
            items: { [weak controller] in controller?.allItems ?? [] },
            theme: { ThemeCenter.shared.theme },
            schedule: Self.schedule,
            openSettingsFile: { center.openInEditor() },
            revealSettingsFile: { NSWorkspace.shared.activateFileViewerSelecting([center.fileURL]) },
            chooseFolder: { [weak self] completion in self?.chooseFolder(completion) }
        )
        // Its own icon provider: the launcher's `onLoad` belongs to the launcher.
        return SettingsWindowController(
            environment: environment,
            icons: LiveIconProvider(theme: { ThemeCenter.shared.theme }),
            hotkeys: hotkeys,
            keyCode: LauncherController.layoutKeyCode
        )
    }

    /// A folder picker, as a sheet on the settings window; paths in the home folder use "~".
    private func chooseFolder(_ completion: @escaping @MainActor (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                completion((url.path as NSString).abbreviatingWithTildeInPath)
            }
        }
        if let window = settingsWindow?.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}

/// One `LauncherEnvironment.schedule` job; cancelling drops the work before it runs.
@MainActor
private final class ScheduledWork {
    private var work: (@MainActor () -> Void)?

    init(_ work: @escaping @MainActor () -> Void) {
        self.work = work
    }

    func run() {
        let work = self.work
        self.work = nil
        work?()
    }

    func cancel() {
        work = nil
    }
}
