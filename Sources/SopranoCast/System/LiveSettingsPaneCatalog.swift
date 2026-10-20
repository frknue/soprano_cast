import AppKit
import IOKit
import IOKit.ps
import LocalAuthentication
import SopranoCastCore

/// The System Settings panes, one item each (Bluetooth, Wi‑Fi, Displays, …), like Raycast's
/// System Settings extension.
///
/// One scan at `start()` reads every settings extension in /System/Library/ExtensionKit
/// and every third-party `.prefPane`; the panes only change with macOS updates, so there
/// is no live watching. The scan runs off the main thread and reports through `onChange`.
@MainActor
final class LiveSettingsPaneCatalog: ItemSource {
    /// Where macOS keeps its settings extensions (`.appex`).
    nonisolated static let extensionDirectories = ["/System/Library/ExtensionKit/Extensions"]

    /// Where third-party preference panes (`.prefPane`) are installed.
    nonisolated static let preferencePaneDirectories = ["/Library/PreferencePanes", "~/Library/PreferencePanes"]

    private(set) var items: [CastItem] = []
    var onChange: (() -> Void)?

    private var isRunning = false
    /// Bumped by `stop()` so a scan finishing afterwards is dropped.
    private var generation = 0

    init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let generation = self.generation
        let extensionDirectories = Self.extensionDirectories
        let preferencePaneDirectories = Self.preferencePaneDirectories.map { ($0 as NSString).expandingTildeInPath }
        Task.detached(priority: .utility) { [weak self] in
            let items = LiveSettingsPaneCatalog.collect(
                extensionDirectories: extensionDirectories,
                preferencePaneDirectories: preferencePaneDirectories,
                facts: LiveSettingsPaneCatalog.currentFacts(),
                preferredLanguages: Locale.preferredLanguages,
                preference: LiveSettingsPaneCatalog.preference(domain:key:)
            )
            await self?.finishScan(items, generation: generation)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
    }

    private func finishScan(_ newItems: [CastItem], generation: Int) {
        guard generation == self.generation else { return }
        if newItems != items {
            items = newItems
            onChange?()
        }
    }

    // MARK: - Scanning (any thread)

    /// Every settings extension in `extensionDirectories` and every `.prefPane` in
    /// `preferencePaneDirectories`, one item per id (extensions first), sorted by title, then id.
    nonisolated static func collect(
        extensionDirectories: [String],
        preferencePaneDirectories: [String],
        facts: SettingsPaneFacts,
        preferredLanguages: [String],
        preference: (_ domain: String, _ key: String) -> Bool?
    ) -> [CastItem] {
        var found: [CastItem] = []
        for path in extensionDirectories.flatMap({ bundlePaths(in: $0, pathExtension: "appex") }) {
            guard let info = infoPlist(atBundlePath: path) else { continue }
            let item = SettingsPanes.extensionItem(
                path: path,
                info: info,
                infoStrings: localizedTables(named: "InfoPlist", inBundleAt: path),
                localizable: localizedTables(named: "Localizable", inBundleAt: path),
                preferredLanguages: preferredLanguages,
                facts: facts,
                preference: preference
            )
            if let item { found.append(item) }
        }
        for path in preferencePaneDirectories.flatMap({ bundlePaths(in: $0, pathExtension: "prefpane") }) {
            guard let info = infoPlist(atBundlePath: path) else { continue }
            let item = SettingsPanes.legacyItem(
                path: path,
                info: info,
                infoStrings: localizedTables(named: "InfoPlist", inBundleAt: path),
                preferredLanguages: preferredLanguages
            )
            if let item { found.append(item) }
        }
        var seen = Set<ItemID>()
        return found.filter { seen.insert($0.id).inserted }.sorted { lhs, rhs in
            switch lhs.title.localizedStandardCompare(rhs.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
    }

    /// The bundles directly in `directory` whose extension is `pathExtension` (any case).
    nonisolated static func bundlePaths(in directory: String, pathExtension: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return names.sorted()
            .filter { !$0.hasPrefix(".") && ($0 as NSString).pathExtension.lowercased() == pathExtension }
            .map { (directory as NSString).appendingPathComponent($0) }
    }

    /// The bundle's Contents/Info.plist; nil when it has none.
    nonisolated static func infoPlist(atBundlePath path: String) -> [String: Any]? {
        propertyList(at: (path as NSString).appendingPathComponent("Contents/Info.plist"))
    }

    /// A bundle's localized strings table, locale code → table: the compiled
    /// `Resources/<name>.loctable`, else every `Resources/<locale>.lproj/<name>.strings`.
    /// [:] when the bundle has neither.
    nonisolated static func localizedTables(named name: String, inBundleAt path: String) -> [String: [String: Any]] {
        let resources = (path as NSString).appendingPathComponent("Contents/Resources")
        if let loctable = propertyList(at: (resources as NSString).appendingPathComponent("\(name).loctable")) {
            var tables: [String: [String: Any]] = [:]
            for (locale, value) in loctable where locale != SettingsPanes.provenanceKey {
                if let table = value as? [String: Any] { tables[locale] = table }
            }
            return tables
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: resources) else { return [:] }
        var tables: [String: [String: Any]] = [:]
        for folder in names where (folder as NSString).pathExtension == "lproj" {
            let stringsPath = ((resources as NSString).appendingPathComponent(folder) as NSString)
                .appendingPathComponent("\(name).strings")
            if let table = propertyList(at: stringsPath) {
                tables[(folder as NSString).deletingPathExtension] = table
            }
        }
        return tables
    }

    /// The dictionary in the (XML, binary or old-style) property list file at `path`.
    nonisolated private static func propertyList(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    // MARK: - Facts (any thread)

    /// The hardware and user facts settings extensions show or hide panes by.
    nonisolated static func currentFacts() -> SettingsPaneFacts {
        SettingsPaneFacts(values: [
            "powersource.battery": hasInternalBattery(),
            "device.touchID": hasTouchID(),
            "user.isguest": NSUserName() == "Guest",
            "device.cddvd": hasOpticalDrive(),
        ])
    }

    /// A Bool default of another app, nil when unset or not a Bool.
    nonisolated static func preference(domain: String, key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
    }

    /// Whether any power source is an internal battery (a laptop).
    nonisolated private static func hasInternalBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            else { return false }
            return description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    /// Whether the Mac has a Touch ID sensor. `biometryType` is set by the policy check even
    /// when it fails (no fingerprints enrolled, locked out), so the result is the hardware's.
    nonisolated private static func hasTouchID() -> Bool {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType == .touchID
    }

    /// Whether a CD, DVD or Blu-ray drive is attached.
    nonisolated private static func hasOpticalDrive() -> Bool {
        ["IOCompactDiscServices", "IODVDServices", "IOBDServices"].contains { className in
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS
            else { return false }
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return false }
            IOObjectRelease(service)
            return true
        }
    }
}
