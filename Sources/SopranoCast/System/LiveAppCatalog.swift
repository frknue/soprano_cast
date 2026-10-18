import AppKit
import OSLog
import SopranoCastCore

private let catalogLog = Logger(subsystem: "com.soprano.cast", category: "apps")

/// The installed applications, live.
///
/// A direct scan of the application folders runs at `start()` so apps are listed before
/// Spotlight answers (and when Spotlight indexing is off); an `NSMetadataQuery` over the
/// same folders then keeps the list current as apps are installed, updated or removed.
/// Every change rescans off the main thread and reports through one coalesced `onChange`.
@MainActor
final class LiveAppCatalog: ItemSource {
    /// The folders Raycast searches; each is searched with its subfolders (Utilities,
    /// vendor folders).
    nonisolated static let standardDirectories = [
        "/Applications",
        "/System/Applications",
        "~/Applications",
        "/System/Library/CoreServices/Applications",
    ]

    /// Finder lives in /System/Library/CoreServices next to hundreds of agents (Dock,
    /// loginwindow, …), so that folder contributes only Finder itself.
    nonisolated static let finderPath = "/System/Library/CoreServices/Finder.app"

    /// How deep the direct scan descends into plain folders ("/Applications/Adobe X/").
    nonisolated static let scanDepth = 3

    /// Folder extensions of bundles; an app inside one of these is part of another bundle.
    nonisolated static let bundleExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "kext", "plugin", "prefpane", "systemextension", "xpc",
    ]

    private(set) var items: [CastItem] = []
    var onChange: (() -> Void)?

    private var extraDirectories: [String]
    private var query: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []
    /// The bundle paths Spotlight reported last.
    private var spotlightPaths: [String] = []
    private var isRunning = false
    /// Bumped by `stop()` so a rescan finishing afterwards is dropped.
    private var generation = 0
    private var rescanInFlight = false
    /// Another change arrived while a rescan ran; rescan once more when it lands.
    private var rescanPending = false

    init(extraDirectories: [String]) {
        self.extraDirectories = Self.normalized(extraDirectories)
    }

    /// `settings.applicationDirectories` changed: restarts the query over the new folders.
    func setExtraDirectories(_ directories: [String]) {
        let normalized = Self.normalized(directories)
        guard normalized != extraDirectories else { return }
        extraDirectories = normalized
        guard isRunning else { return }
        stopQuery()
        spotlightPaths = []
        startQuery()
        rescan()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startQuery()
        rescan()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        rescanInFlight = false
        rescanPending = false
        stopQuery()
    }

    // MARK: - Spotlight

    private var directories: [String] {
        var seen = Set<String>()
        return (Self.normalized(Self.standardDirectories) + extraDirectories).filter { seen.insert($0).inserted }
    }

    private func startQuery() {
        let scopes = directories.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        guard !scopes.isEmpty else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", "com.apple.application-bundle")
        query.searchScopes = scopes.map { URL(fileURLWithPath: $0, isDirectory: true) }
        query.notificationBatchingInterval = 0.5
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            queryObservers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.queryDidChange()
                }
            })
        }
        self.query = query
        if !query.start() {
            catalogLog.error("Spotlight application query did not start; using the folder scan only")
        }
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        for observer in queryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        queryObservers = []
    }

    private func queryDidChange() {
        guard let query else { return }
        query.disableUpdates()
        spotlightPaths = (0..<query.resultCount).compactMap { index in
            (query.result(at: index) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
        }
        query.enableUpdates()
        rescan()
    }

    // MARK: - Rescanning

    private func rescan() {
        guard isRunning else { return }
        if rescanInFlight {
            rescanPending = true
            return
        }
        rescanInFlight = true
        let generation = self.generation
        let directories = self.directories
        let spotlightPaths = self.spotlightPaths
        Task.detached(priority: .utility) { [weak self] in
            let items = LiveAppCatalog.collect(directories: directories, bundlePaths: spotlightPaths)
            await self?.finishRescan(items, generation: generation)
        }
    }

    private func finishRescan(_ newItems: [CastItem], generation: Int) {
        guard generation == self.generation else { return }
        rescanInFlight = false
        if newItems != items {
            items = newItems
            onChange?()
        }
        if rescanPending {
            rescanPending = false
            rescan()
        }
    }

    // MARK: - Scanning (any thread)

    /// Every app in `directories` (scanned directly), Finder, and `bundlePaths` (Spotlight's
    /// answer), one item per bundle id.
    nonisolated static func collect(directories: [String], bundlePaths: [String]) -> [CastItem] {
        var seen = Set<String>()
        let paths = (directories.flatMap { appPaths(in: $0, depth: scanDepth) } + [finderPath] + bundlePaths)
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { seen.insert($0).inserted }
        let entries: [(CastItem, path: String)] = paths.compactMap { path in
            guard let plist = infoPlist(atBundlePath: path),
                  let item = entry(forBundleAt: URL(fileURLWithPath: path), infoPlist: plist) else { return nil }
            return (item, path: path)
        }
        return deduplicated(entries)
    }

    /// The `.app` bundles in `directory` and, up to `depth` levels, in its plain subfolders.
    nonisolated static func appPaths(in directory: String, depth: Int) -> [String] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        var paths: [String] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let path = (directory as NSString).appendingPathComponent(name)
            let pathExtension = (name as NSString).pathExtension.lowercased()
            if pathExtension == "app" {
                paths.append(path)
                continue
            }
            guard depth > 0, !bundleExtensions.contains(pathExtension) else { continue }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                paths += appPaths(in: path, depth: depth - 1)
            }
        }
        return paths
    }

    /// The bundle's Info.plist: macOS layout, then the wrapper of an iPhone/iPad app, then
    /// a flat bundle. nil when the folder has none (not an app).
    nonisolated static func infoPlist(atBundlePath path: String) -> [String: Any]? {
        for relative in ["Contents/Info.plist", "WrappedBundle/Info.plist", "Info.plist"] {
            let url = URL(fileURLWithPath: path).appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url) else { continue }
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                return plist
            }
        }
        return nil
    }

    // MARK: - Pure parts

    /// The item for the app bundle at `url` with its Info.plist; nil for apps nested in
    /// another bundle and `LSBackgroundOnly` apps.
    nonisolated static func entry(forBundleAt url: URL, infoPlist: [String: Any]) -> CastItem? {
        let path = url.standardizedFileURL.path
        guard !isNested(path), !isBackgroundOnly(infoPlist["LSBackgroundOnly"]) else { return nil }
        let bundleID = (infoPlist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = displayName(ofBundleAt: path)
        var keywords: [String] = []
        for key in ["CFBundleName", "CFBundleExecutable"] {
            guard let value = (infoPlist[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value.caseInsensitiveCompare(title) != .orderedSame,
                  !keywords.contains(value) else { continue }
            keywords.append(value)
        }
        let folder = (path as NSString).deletingLastPathComponent
        return CastItem(
            id: ItemID(kind: .application, key: bundleID.isEmpty ? path : bundleID),
            title: title,
            subtitle: (folder as NSString).abbreviatingWithTildeInPath,
            keywords: keywords,
            icon: .file(path: path)
        )
    }

    /// One item per id, keeping the copy in /Applications, then /System/Applications, then
    /// the one with the shortest path. Sorted by title, then id.
    nonisolated static func deduplicated(_ items: [(CastItem, path: String)]) -> [CastItem] {
        var best: [ItemID: (CastItem, path: String)] = [:]
        for entry in items {
            if let current = best[entry.0.id], !isPreferred(entry.path, over: current.path) { continue }
            best[entry.0.id] = entry
        }
        return best.values.map { $0.0 }.sorted { lhs, rhs in
            switch lhs.title.localizedStandardCompare(rhs.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
    }

    /// Whether an ancestor folder of `path` is a bundle (Xcode.app/Contents/Applications/…).
    nonisolated static func isNested(_ path: String) -> Bool {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        let ancestors = (trimmed as NSString).pathComponents.dropLast()
        return ancestors.contains { bundleExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    // MARK: - Helpers

    nonisolated private static func isPreferred(_ path: String, over other: String) -> Bool {
        (preferenceRank(path), path.count, path) < (preferenceRank(other), other.count, other)
    }

    nonisolated private static func preferenceRank(_ path: String) -> Int {
        if path.hasPrefix("/Applications/") { return 0 }
        if path.hasPrefix("/System/Applications/") { return 1 }
        return 2
    }

    nonisolated private static func isBackgroundOnly(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        case let text as String: ["1", "yes", "true"].contains(text.lowercased())
        default: false
        }
    }

    /// Finder's name for the bundle (localized, extension hidden) without ".app".
    nonisolated private static func displayName(ofBundleAt path: String) -> String {
        var name = FileManager.default.displayName(atPath: path)
        if name.lowercased().hasSuffix(".app") { name.removeLast(4) }
        if name.isEmpty {
            name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        return name
    }

    /// Absolute, ~-expanded, standardized, unique, in order.
    nonisolated private static func normalized(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
            .filter { seen.insert($0).inserted }
    }
}
