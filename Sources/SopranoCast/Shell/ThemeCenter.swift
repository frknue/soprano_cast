import AppKit
import SopranoCastCore

/// The live theme (Soprano Tab's `ThemeCenter`).
///
/// `theme: "soprano"` follows the `theme` and `appearance` keys of Soprano's
/// settings.json, watched live. `folio` (also what a missing or unknown id becomes)
/// resolves to Folio Paper or Folio Ink from the appearance: Soprano's `appearance` while
/// following Soprano unless it is `system`, else the system's. Observers fire when the
/// resolved palette changes, so a system light/dark switch reaches them under `folio`.
@MainActor
final class ThemeCenter {
    static let shared = ThemeCenter()

    /// The `theme` value that follows Soprano.
    nonisolated static let followSopranoID = "soprano"
    /// Every Soprano theme id Cast's settings.json accepts besides `followSopranoID`.
    static var knownThemeIDs: Set<String> { Set(AppTheme.options.map(\.id)) }

    /// Soprano's settings.json, read while the theme follows Soprano.
    let sopranoSettingsURL: URL
    /// The resolved palette.
    private(set) var theme = AppTheme.folioPaper

    private let settingsCenter: SettingsCenter
    private let systemAppearance: @MainActor () -> AppTheme.Appearance
    private var sopranoWatcher: ConfigFileWatcher?
    private var appearanceObservation: NSKeyValueObservation?
    private let observers = ObserverList<Void>()
    private var isStarted = false

    init(
        sopranoSettingsURL: URL = SettingsFile.sopranoURL(),
        settings: SettingsCenter = .shared,
        systemAppearance: @escaping @MainActor () -> AppTheme.Appearance = {
            AppTheme.Appearance(NSApplication.shared.effectiveAppearance)
        }
    ) {
        self.sopranoSettingsURL = sopranoSettingsURL
        self.settingsCenter = settings
        self.systemAppearance = systemAppearance
    }

    /// Applies the current settings and follows their changes and the system appearance.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        apply()
        settingsCenter.addObserver(self) { [weak self] in
            self?.apply()
        }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.systemAppearanceDidChange()
            }
        }
    }

    /// Handlers fire after the resolved theme changes, until `owner` is deallocated.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        observers.add(owner) { _ in handler() }
    }

    /// The system switched between light and dark: `folio` re-resolves.
    func systemAppearanceDidChange() {
        apply()
    }

    /// The palette for Cast's `theme` setting. `soprano` reads `soprano` (nil: Soprano's
    /// file is missing or unreadable, which follows Folio and the system).
    static func resolve(
        themeID: String,
        soprano: SopranoThemeSettings?,
        system: AppTheme.Appearance
    ) -> AppTheme {
        guard themeID == followSopranoID else {
            return AppTheme.theme(for: themeID, appearance: system)
        }
        let followed = soprano ?? SopranoThemeSettings()
        let appearance: AppTheme.Appearance = switch followed.appearance {
        case .light: .light
        case .dark: .dark
        case .system: system
        }
        return AppTheme.theme(for: followed.theme ?? AppTheme.folioId, appearance: appearance)
    }

    private func apply() {
        let themeID = settingsCenter.settings.theme
        let followsSoprano = themeID == Self.followSopranoID
        updateSopranoWatcher(enabled: followsSoprano)
        let previous = theme.id
        theme = Self.resolve(
            themeID: themeID,
            soprano: followsSoprano ? readSopranoSettings() : nil,
            system: systemAppearance()
        )
        if theme.id != previous {
            observers.notify(())
        }
    }

    private func reloadSopranoTheme() {
        guard sopranoWatcher != nil else { return }
        apply()
    }

    private func readSopranoSettings() -> SopranoThemeSettings? {
        guard let text = try? SettingsFile.read(at: sopranoSettingsURL) else { return nil }
        return SopranoThemeSettings.read(text: text)
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
