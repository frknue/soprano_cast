import AppKit
import OSLog
import SopranoCastCore

private let appActionsLog = Logger(subsystem: "com.soprano.cast", category: "apps")

/// Opening, quitting and hiding the app behind an application item (`app:<bundle id>` or
/// `app:<path>`).
@MainActor
enum AppActions {
    /// How long a hidden app takes to put its windows back on screen after `unhide()`.
    private static let unhideSettleDelay: Duration = .milliseconds(300)

    /// Brings the app forward the way a Dock click does: a running app is unhidden and
    /// activated with all its windows; when it then has no window on screen it is opened
    /// again, which sends it the reopen event (Finder, Chrome, Notes answer with a new
    /// window, minimized windows come back). An app that isn't running is launched.
    static func open(_ item: CastItem) {
        guard let app = runningApplication(for: item) else {
            guard let url = bundleURL(for: item) else {
                appActionsLog.error("No application for \(item.id.rawValue, privacy: .public)")
                return
            }
            openApplication(at: url)
            return
        }
        let fallbackURL = bundleURL(for: item)
        guard app.isHidden else {
            app.activate(options: [.activateAllWindows])
            reopenIfWindowless(app, fallbackURL: fallbackURL)
            return
        }
        app.unhide()
        app.activate(options: [.activateAllWindows])
        // A hidden app's windows are not on screen until the unhide has been processed.
        let pid = app.processIdentifier
        Task { @MainActor in
            try? await Task.sleep(for: unhideSettleDelay)
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            reopenIfWindowless(app, fallbackURL: fallbackURL)
        }
    }

    /// Opens the app again when it shows no window, so it gets the reopen event.
    private static func reopenIfWindowless(_ app: NSRunningApplication, fallbackURL: URL?) {
        guard !hasOnScreenWindows(pid: app.processIdentifier),
              let url = app.bundleURL ?? fallbackURL else { return }
        openApplication(at: url)
    }

    static func isRunning(_ item: CastItem) -> Bool {
        !runningApplications(for: item).isEmpty
    }

    /// Whether the app is the frontmost one and shows a window on screen. A frontmost app
    /// without windows (Finder on the desktop) doesn't count: its hotkey opens a window.
    static func isFrontmost(_ item: CastItem) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = front.processIdentifier
        return runningApplications(for: item).contains { $0.processIdentifier == pid }
            && hasOnScreenWindows(pid: pid)
    }

    static func quit(_ item: CastItem) {
        for app in runningApplications(for: item) {
            app.terminate()
        }
    }

    static func hide(_ item: CastItem) {
        for app in runningApplications(for: item) {
            app.hide()
        }
    }

    /// The bundle the item lists (the catalog's chosen copy), else the running app's,
    /// else LaunchServices' answer for the bundle id.
    static func bundleURL(for item: CastItem) -> URL? {
        guard item.kind == .application else { return nil }
        if case .file(let path) = item.icon, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let key = item.id.key
        if key.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: key) ? URL(fileURLWithPath: key) : nil
        }
        if let url = runningApplications(for: item).first?.bundleURL {
            return url
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: key)
    }

    // MARK: - Helpers

    /// The app's running instances: by bundle id, or by bundle path for `app:<path>` items.
    private static func runningApplications(for item: CastItem) -> [NSRunningApplication] {
        guard item.kind == .application else { return [] }
        let key = item.id.key
        let apps: [NSRunningApplication]
        if key.hasPrefix("/") {
            let path = URL(fileURLWithPath: key).standardizedFileURL.path
            apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.path == path }
        } else {
            apps = NSRunningApplication.runningApplications(withBundleIdentifier: key)
        }
        return apps.filter { !$0.isTerminated }
    }

    /// The instance to bring forward: one that can show windows when there is a choice.
    private static func runningApplication(for item: CastItem) -> NSRunningApplication? {
        let apps = runningApplications(for: item)
        return apps.first { $0.activationPolicy == .regular } ?? apps.first
    }

    /// Whether `pid` owns a visible normal-level window on the current Space.
    private static func hasOnScreenWindows(pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { info in
            (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0
        }
    }

    private static func openApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                appActionsLog.error("Opening \(url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
