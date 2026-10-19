import AppKit
import SopranoCastCore
import UniformTypeIdentifiers

/// Runs items and their non-settings actions on the real system.
@MainActor
final class LiveItemRunner: ItemRunning {
    /// Apps that would run a script instead of showing it; Edit Script uses the plain-text
    /// editor when one of them is the file's default app.
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty",
    ]

    private let windowManager: WindowManaging
    private let scripts: ScriptCatalog
    private let scriptRunner: ScriptRunner
    private let systemCommands: SystemCommandRunner
    private let settings: @MainActor () -> CastSettings
    private let castCommand: @MainActor (CastCommand) -> RunOutcome

    init(
        windowManager: WindowManaging,
        scripts: ScriptCatalog,
        scriptRunner: ScriptRunner,
        systemCommands: SystemCommandRunner,
        settings: @escaping @MainActor () -> CastSettings,
        castCommand: @escaping @MainActor (CastCommand) -> RunOutcome
    ) {
        self.windowManager = windowManager
        self.scripts = scripts
        self.scriptRunner = scriptRunner
        self.systemCommands = systemCommands
        self.settings = settings
        self.castCommand = castCommand
    }

    func run(_ item: CastItem, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void) {
        guard item.kind == .script else {
            completion(runImmediately(item, arguments: arguments))
            return
        }
        guard let script = scripts.script(for: item.id) else {
            completion(.toast("Script not found", isError: true))
            return
        }
        scriptRunner.execute(script, arguments: arguments) { [weak scripts = self.scripts] execution in
            if script.mode == .inline {
                scripts?.recordInlineResult(execution, for: script.path)
            }
            completion(ScriptRunner.outcome(for: script, execution: execution))
        }
    }

    func perform(_ action: ItemActionID, on item: CastItem) -> RunOutcome {
        switch action {
        case .open:
            // Scripts finish later; the launcher runs them through `run`.
            guard item.kind != .script else { return .toast("Press ↵ to run this script", isError: false) }
            return runImmediately(item, arguments: [])
        case .showInFinder:
            guard let url = fileURL(for: item) else { return .toast("Nothing to show in Finder", isError: true) }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return .done(closeLauncher: true)
        case .copyPath:
            guard let url = fileURL(for: item) else { return .toast("No path to copy", isError: true) }
            return copy(url.path)
        case .copyBundleID:
            guard let bundleID = bundleIdentifier(for: item) else { return .toast("No bundle identifier", isError: true) }
            return copy(bundleID)
        case .copyLink:
            guard let quicklink = quicklink(for: item) else { return .toast("Quicklink not found", isError: true) }
            return copy(quicklink.link)
        case .copyName, .copyResult:
            return copy(item.title)
        case .quitApplication:
            AppActions.quit(item)
            return .done(closeLauncher: true)
        case .hideApplication:
            AppActions.hide(item)
            return .done(closeLauncher: true)
        case .editScript:
            guard item.kind == .script else { return .toast("Not a script command", isError: true) }
            editScript(at: item.id.key)
            return .done(closeLauncher: true)
        case .toggleFavorite, .moveFavoriteUp, .moveFavoriteDown, .setHotkey, .deleteHotkey,
             .setAlias, .deleteAlias, .disableCommand:
            // The launcher controller's (settings edits); never routed here.
            return .done(closeLauncher: false)
        }
    }

    func isRunning(_ item: CastItem) -> Bool {
        item.kind == .application && AppActions.isRunning(item)
    }

    func isFrontmost(_ item: CastItem) -> Bool {
        item.kind == .application && AppActions.isFrontmost(item)
    }

    // MARK: - Running

    /// Every kind but scripts, which finish asynchronously.
    private func runImmediately(_ item: CastItem, arguments: [String]) -> RunOutcome {
        switch item.kind {
        case .application:
            AppActions.open(item)
            return .done(closeLauncher: true)
        case .systemCommand:
            guard let command = SystemCommand(rawValue: item.id.key) else { return unknown(item) }
            return systemCommands.run(command)
        case .windowCommand:
            guard let command = WindowCommand(rawValue: item.id.key) else { return unknown(item) }
            if let message = windowManager.perform(command, settings: settings().windowManagement) {
                return .hud(message)
            }
            return .done(closeLauncher: true)
        case .quicklink:
            guard let quicklink = quicklink(for: item) else { return .toast("Quicklink not found", isError: true) }
            return QuicklinkOpener.open(quicklink, arguments: arguments)
        case .castCommand:
            guard let command = CastCommand(rawValue: item.id.key) else { return unknown(item) }
            switch command {
            case .searchGoogle:
                return QuicklinkOpener.open(urlString: Self.searchURL(Self.googleSearch, query: arguments.first ?? ""), openWith: nil)
            case .searchDuckDuckGo:
                return QuicklinkOpener.open(urlString: Self.searchURL(Self.duckDuckGoSearch, query: arguments.first ?? ""), openWith: nil)
            case .openSettings, .reloadScripts, .quit:
                return castCommand(command)
            }
        case .calculator:
            return copy(item.title)
        case .script, nil:
            return unknown(item)
        }
    }

    static let googleSearch = "https://www.google.com/search?q="
    static let duckDuckGoSearch = "https://duckduckgo.com/?q="

    /// `base` followed by `query` (trimmed) percent-encoded as one query value.
    static func searchURL(_ base: String, query: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return base + (trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }

    private func unknown(_ item: CastItem) -> RunOutcome {
        .toast("Unknown command \(item.id.rawValue)", isError: true)
    }

    // MARK: - Actions

    private func quicklink(for item: CastItem) -> Quicklink? {
        guard item.kind == .quicklink else { return nil }
        return settings().quicklinks.first { $0.id == item.id.key }
    }

    /// The app bundle or script file an item stands for.
    private func fileURL(for item: CastItem) -> URL? {
        switch item.kind {
        case .application: AppActions.bundleURL(for: item)
        case .script: URL(fileURLWithPath: item.id.key)
        default: nil
        }
    }

    private func bundleIdentifier(for item: CastItem) -> String? {
        guard item.kind == .application else { return nil }
        if !item.id.key.hasPrefix("/") { return item.id.key }
        return AppActions.bundleURL(for: item).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func copy(_ text: String) -> RunOutcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .hud("Copied")
    }

    /// Opens the script in its default app, or in the plain-text editor when that app is a
    /// terminal (which would run it).
    private func editScript(at path: String) {
        let url = URL(fileURLWithPath: path)
        let workspace = NSWorkspace.shared
        if let handler = workspace.urlForApplication(toOpen: url),
           let handlerID = Bundle(url: handler)?.bundleIdentifier,
           !Self.terminalBundleIDs.contains(handlerID) {
            workspace.open(url)
            return
        }
        guard let editor = workspace.urlForApplication(toOpen: UTType.plainText) else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
