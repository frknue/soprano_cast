import AppKit
import SopranoCastCore

/// The live theme (Soprano Tab's `ThemeCenter`).
///
/// `theme: "soprano"` follows the `theme` and `appearance` keys of Soprano's
/// settings.json, watched live. `folio` (also what a missing or unknown id becomes)
/// resolves to Folio Paper or Folio Ink from the appearance: Soprano's `appearance` while
/// following Soprano unless it is `system`, else the system's. Observers fire when the
/// resolved palette changes, so a system light/dark switch reaches them under `folio`.
///
/// The app appearance (menus, pop-ups, sheets, the status-item menu) is the resolved
/// theme's; it is unset (nil) only while the palette follows macOS, so the system's
/// light/dark switch reaches `NSApp.effectiveAppearance`.
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
    private let setApplicationAppearance: @MainActor (NSAppearance?) -> Void
    private var sopranoWatcher: ConfigFileWatcher?
    private var appearanceObservation: NSKeyValueObservation?
    /// The appearance last given to the app; `.none` until the first `apply()`.
    private var appliedAppearance: NSAppearance.Name??
    private let observers = ObserverList<Void>()
    private var isStarted = false

    init(
        sopranoSettingsURL: URL = SettingsFile.sopranoURL(),
        settings: SettingsCenter = .shared,
        systemAppearance: @escaping @MainActor () -> AppTheme.Appearance = {
            AppTheme.Appearance(NSApplication.shared.effectiveAppearance)
        },
        setApplicationAppearance: @escaping @MainActor (NSAppearance?) -> Void = {
            NSApplication.shared.appearance = $0
        }
    ) {
        self.sopranoSettingsURL = sopranoSettingsURL
        self.settingsCenter = settings
        self.systemAppearance = systemAppearance
        self.setApplicationAppearance = setApplicationAppearance
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

    /// Whether the palette for `themeID` comes from the macOS appearance: `folio` or an
    /// unknown id, or following Soprano while Soprano's `appearance` is `system` and its
    /// theme is not a concrete palette.
    static func followsSystem(themeID: String, soprano: SopranoThemeSettings?) -> Bool {
        let isPalette: (String) -> Bool = { id in AppTheme.allThemes.contains { $0.id == id } }
        guard themeID == followSopranoID else { return !isPalette(themeID) }
        let followed = soprano ?? SopranoThemeSettings()
        return followed.appearance == .system && !isPalette(followed.theme ?? AppTheme.folioId)
    }

    private func apply() {
        let themeID = settingsCenter.settings.theme
        let followsSoprano = themeID == Self.followSopranoID
        updateSopranoWatcher(enabled: followsSoprano)
        let soprano = followsSoprano ? readSopranoSettings() : nil
        let followsSystem = Self.followsSystem(themeID: themeID, soprano: soprano)
        // Unpinned first, so `systemAppearance` reads macOS rather than the last pin.
        if followsSystem {
            setApplicationAppearanceIfChanged(nil)
        }
        let previous = theme.id
        theme = Self.resolve(themeID: themeID, soprano: soprano, system: systemAppearance())
        if !followsSystem {
            setApplicationAppearanceIfChanged(theme.appearance.nsAppearance)
        }
        if theme.id != previous {
            observers.notify(())
        }
    }

    /// Every `NSApp.appearance` set, even an unchanged one, fires the `effectiveAppearance`
    /// observation, which calls `apply()` again: an unconditional set re-themes every
    /// window in an endless loop.
    private func setApplicationAppearanceIfChanged(_ appearance: NSAppearance?) {
        guard appliedAppearance != .some(appearance?.name) else { return }
        appliedAppearance = .some(appearance?.name)
        setApplicationAppearance(appearance)
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
