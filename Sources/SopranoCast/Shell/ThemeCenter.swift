import AppKit
import SopranoCastCore

/// The live theme (Soprano Tab's `ThemeCenter`).
///
/// `theme: "soprano"` follows the `theme` key of Soprano's settings.json, watched live;
/// Mission Control when that file or key is missing or unknown.
@MainActor
final class ThemeCenter {
    static let shared = ThemeCenter()

    /// Soprano's settings.json, read while the theme follows Soprano.
    let sopranoSettingsURL: URL
    /// The current theme (settings.json `theme`).
    private(set) var theme = AppTheme.missionControl

    private let settingsCenter: SettingsCenter
    private var sopranoWatcher: ConfigFileWatcher?
    private let observers = ObserverList<Void>()
    private var isStarted = false

    init(sopranoSettingsURL: URL = SettingsFile.sopranoURL(), settings: SettingsCenter = .shared) {
        self.sopranoSettingsURL = sopranoSettingsURL
        self.settingsCenter = settings
    }

    /// Applies the current settings and follows their changes.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        apply()
        settingsCenter.addObserver(self) { [weak self] in
            self?.apply()
        }
    }

    /// Handlers fire after the theme changes, until `owner` is deallocated.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        observers.add(owner) { _ in handler() }
    }

    private func apply() {
        let themeID = settingsCenter.settings.theme
        let followsSoprano = themeID == "soprano"
        updateSopranoWatcher(enabled: followsSoprano)
        let previous = theme.id
        theme = followsSoprano
            ? readSopranoTheme()
            : AppTheme.allThemes.first { $0.id == themeID } ?? .missionControl
        if theme.id != previous {
            observers.notify(())
        }
    }

    private func reloadSopranoTheme() {
        guard sopranoWatcher != nil else { return }
        apply()
    }

    /// Soprano's settings.json shares the top-level `theme` key and its ids, so the
    /// public JSONC resolver reads it; every other Soprano key is ignored.
    private func readSopranoTheme() -> AppTheme {
        guard let text = try? SettingsFile.read(at: sopranoSettingsURL) else { return .missionControl }
        let ids = Set(AppTheme.allThemes.map(\.id))
        guard let id = SettingsResolver.resolve(text: text, knownThemeIDs: ids).settings?.theme else {
            return .missionControl
        }
        return AppTheme.allThemes.first { $0.id == id } ?? .missionControl
    }

    private func updateSopranoWatcher(enabled: Bool) {
        if enabled {
            guard sopranoWatcher == nil else { return }
            let watcher = ConfigFileWatcher(url: sopranoSettingsURL) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reloadSopranoTheme()
                }
            }
            watcher.start()
            sopranoWatcher = watcher
        } else {
            sopranoWatcher?.stop()
            sopranoWatcher = nil
        }
    }
}
