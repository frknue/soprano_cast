import AppKit
import SopranoCastCore

/// The script commands of the configured folders (Raycast's "Script Directories").
///
/// Each folder and its direct subfolders are scanned on a background queue for regular
/// files whose metadata parses (templates — names containing ".template." — skipped). The
/// folders are watched; changes rescan after a short debounce. Inline-mode scripts (the
/// first `maxInlineScripts`) run on load and every `refreshSeconds`, and their last output
/// line replaces the subtitle.
@MainActor
final class ScriptCatalog: ItemSource {
    /// Raycast refreshes at most this many inline scripts.
    static let maxInlineScripts = 10
    /// Quiet time after a file-system change before rescanning.
    static let rescanDelay: Duration = .milliseconds(400)

    private(set) var items: [CastItem] = []
    var onChange: (() -> Void)?

    private var directories: [String]
    private let runner: ScriptRunner
    private var isStarted = false
    private var scripts: [ScriptCommand] = []
    private var scriptsByID: [ItemID: ScriptCommand] = [:]
    private var watcher: FileSystemWatcher?
    private var watchedPaths: [String] = []
    private var pendingRescan: Task<Void, Never>?
    /// Bumped per scan; a scan finishing after a newer one started is dropped.
    private var scanGeneration = 0
    /// Last output line per inline script path.
    private var inlineOutputs: [String: String] = [:]
    /// Refresh timers per inline script path, with the interval they were scheduled for.
    private var inlineTimers: [String: (timer: Timer?, refreshSeconds: Int?)] = [:]
    private var inlineRunsInFlight: Set<String> = []

    init(directories: [String], runner: ScriptRunner = ScriptRunner()) {
        self.directories = directories
        self.runner = runner
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reload()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        watcher?.stop()
        watcher = nil
        watchedPaths = []
        pendingRescan?.cancel()
        pendingRescan = nil
        scanGeneration += 1
        for entry in inlineTimers.values { entry.timer?.invalidate() }
        inlineTimers = [:]
    }

    /// New folders from settings; rescans when they differ.
    func setDirectories(_ directories: [String]) {
        guard directories != self.directories else { return }
        self.directories = directories
        if isStarted { reload() }
    }

    /// Rescans every folder now and reruns the inline scripts.
    func reload() {
        guard isStarted else { return }
        pendingRescan?.cancel()
        pendingRescan = nil
        updateWatcher()
        scan(rerunInline: true)
    }

    func script(for id: ItemID) -> ScriptCommand? {
        scriptsByID[id]
    }

    /// Records a run of an inline script started elsewhere (the launcher), so its subtitle
    /// shows the new output.
    func recordInlineResult(_ execution: ScriptExecution, for path: String) {
        guard let line = ScriptOutput.lastLine(execution.output) ?? execution.launchError else { return }
        guard inlineOutputs[path] != line else { return }
        inlineOutputs[path] = line
        rebuildItems()
    }

    // MARK: - Scanning

    private func scan(rerunInline: Bool) {
        scanGeneration += 1
        let generation = scanGeneration
        let directories = Self.resolvedDirectories(self.directories)
        Task {
            let scripts = await Self.scanInBackground(directories: directories)
            guard generation == scanGeneration, isStarted else { return }
            apply(scripts, rerunInline: rerunInline)
        }
    }

    private nonisolated static func scanInBackground(directories: [String]) async -> [ScriptCommand] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ScriptCatalog.scan(directories: directories))
            }
        }
    }

    /// Absolute, standardized folder paths (~ expanded), duplicates removed.
    nonisolated static func resolvedDirectories(_ directories: [String]) -> [String] {
        var seen: Set<String> = []
        return directories.compactMap { directory in
            let trimmed = directory.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let path = ((trimmed as NSString).expandingTildeInPath as NSString).standardizingPath
            guard path.hasPrefix("/"), seen.insert(path).inserted else { return nil }
            return path
        }
    }

    /// Every parsable script in `directories` (absolute) and their direct subfolders, sorted
    /// by title, then path. Runs on any thread.
    nonisolated static func scan(directories: [String]) -> [ScriptCommand] {
        let fileManager = FileManager.default
        var seen: Set<String> = []
        var scripts: [ScriptCommand] = []

        func contents(of folder: String) -> [URL] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            return (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        func consider(_ url: URL, directoryName: String) {
            let path = url.standardizedFileURL.path
            let name = url.lastPathComponent
            guard !name.contains(".template."), !seen.contains(path) else { return }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { return }
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            guard case .success(let script) = ScriptMetadataParser.parse(contents: text, path: path, directoryName: directoryName) else { return }
            seen.insert(path)
            scripts.append(script)
        }

        for directory in directories {
            let folderName = (directory as NSString).lastPathComponent
            for url in contents(of: directory) {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                if values?.isDirectory == true {
                    // One level of subfolders (Raycast's script-commands layout); bundles aren't folders.
                    guard values?.isPackage != true else { continue }
                    for child in contents(of: url.path) {
                        consider(child, directoryName: url.lastPathComponent)
                    }
                } else {
                    consider(url, directoryName: folderName)
                }
            }
        }

        return scripts.sorted { lhs, rhs in
            switch lhs.title.localizedStandardCompare(rhs.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.path < rhs.path
            }
        }
    }

    private func apply(_ scripts: [ScriptCommand], rerunInline: Bool) {
        let paths = Set(scripts.map(\.path))
        inlineOutputs = inlineOutputs.filter { paths.contains($0.key) }
        self.scripts = scripts
        scriptsByID = Dictionary(
            scripts.map { (ItemID(kind: .script, key: $0.path), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        rebuildItems()
        scheduleInlineScripts(rerunAll: rerunInline)
    }

    private func rebuildItems() {
        let items = scripts.map { script in
            CastItem(
                id: ItemID(kind: .script, key: script.path),
                title: script.title,
                subtitle: inlineOutputs[script.path] ?? script.packageName,
                keywords: script.description.map { [$0] } ?? [],
                icon: script.icon ?? .glyph(.script),
                arguments: script.arguments,
                needsConfirmation: script.needsConfirmation
            )
        }
        guard items != self.items else { return }
        self.items = items
        onChange?()
    }

    // MARK: - Watching

    /// Watches the folders that exist right now (FSEvents watches the trees recursively).
    private func updateWatcher() {
        let existing = Self.resolvedDirectories(directories).filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        guard existing != watchedPaths || (watcher == nil && !existing.isEmpty) else { return }
        watcher?.stop()
        watcher = nil
        watchedPaths = existing
        guard !existing.isEmpty else { return }
        watcher = FileSystemWatcher(paths: existing, latency: 0.3) { [weak self] _, _ in
            self?.scheduleRescan()
        }
    }

    private func scheduleRescan() {
        pendingRescan?.cancel()
        pendingRescan = Task { [weak self] in
            try? await Task.sleep(for: Self.rescanDelay)
            guard !Task.isCancelled, let self, self.isStarted else { return }
            self.pendingRescan = nil
            self.scan(rerunInline: false)
        }
    }

    // MARK: - Inline scripts

    /// Runs new (or, with `rerunAll`, every) inline script among the first
    /// `maxInlineScripts` and keeps one refresh timer per script with a `refreshSeconds`.
    private func scheduleInlineScripts(rerunAll: Bool) {
        let inline = Array(scripts.filter { $0.mode == .inline }.prefix(Self.maxInlineScripts))
        let wanted = Dictionary(inline.map { ($0.path, $0.refreshSeconds) }, uniquingKeysWith: { first, _ in first })

        // Gone, or its refresh interval changed (wanted[path] is nil for a gone script).
        for (path, entry) in inlineTimers where wanted[path] != .some(entry.refreshSeconds) {
            entry.timer?.invalidate()
            inlineTimers[path] = nil
        }
        for script in inline {
            let isNew = inlineTimers[script.path] == nil
            if isNew {
                inlineTimers[script.path] = (makeTimer(for: script), script.refreshSeconds)
            }
            if isNew || rerunAll {
                runInline(path: script.path)
            }
        }
    }

    private func makeTimer(for script: ScriptCommand) -> Timer? {
        guard let seconds = script.refreshSeconds, seconds > 0 else { return nil }
        let path = script.path
        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runInline(path: path)
            }
        }
        timer.tolerance = min(TimeInterval(seconds) * 0.1, 5)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Runs one inline script unless its previous run is still going.
    private func runInline(path: String) {
        guard isStarted, let script = scriptsByID[ItemID(kind: .script, key: path)] else { return }
        guard inlineRunsInFlight.insert(path).inserted else { return }
        runner.execute(script, arguments: []) { [weak self] execution in
            guard let self else { return }
            self.inlineRunsInFlight.remove(path)
            guard self.isStarted, self.scriptsByID[ItemID(kind: .script, key: path)] != nil else { return }
            self.recordInlineResult(execution, for: path)
        }
    }
}
