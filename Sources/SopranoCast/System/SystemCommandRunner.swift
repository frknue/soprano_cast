import AppKit
import Darwin
import SopranoCastCore

/// Runs the built-in system commands. Each returns `.hud(<title>)` when it was started, or
/// an error toast. Apple events to Finder and System Events need the Automation permission
/// (macOS asks on first use; `NSAppleEventsUsageDescription` explains why).
@MainActor
final class SystemCommandRunner {
    init() {}

    func run(_ command: SystemCommand) -> RunOutcome {
        let error: String? = switch command {
        case .lockScreen: lockScreen()
        case .sleep: launch("/usr/bin/pmset", ["sleepnow"])
        case .sleepDisplays: launch("/usr/bin/pmset", ["displaysleepnow"])
        case .restart: sendLoginWindowEvent("rest")
        case .shutDown: sendLoginWindowEvent("shut")
        case .logOut: sendLoginWindowEvent("rlgo")
        case .emptyTrash: emptyTrash()
        case .ejectAllDisks: ejectAllDisks()
        case .toggleSystemAppearance: toggleSystemAppearance()
        case .quitAllApplications: quitAllApplications()
        case .hideOtherApplications: hideOtherApplications()
        case .toggleHiddenFiles: toggleHiddenFiles()
        }
        if let error { return .toast(error, isError: true) }
        return .hud(command.title)
    }

    // MARK: - Commands (nil = started)

    private typealias LockScreenFn = @convention(c) () -> Int32

    /// `SACLockScreenImmediate` from the private login.framework (what the menu bar's Lock
    /// Screen calls), else ⌃⌘Q posted as a key event (needs Accessibility).
    private func lockScreen() -> String? {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            let lock = unsafeBitCast(symbol, to: LockScreenFn.self)
            _ = lock()
            return nil
        }
        let qKey: CGKeyCode = 12
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: qKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: qKey, keyDown: false) else {
            return "Couldn't lock the screen"
        }
        down.flags = [.maskControl, .maskCommand]
        up.flags = [.maskControl, .maskCommand]
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return nil
    }

    /// Starts a tool without waiting for it (pmset returns at once, but never block here).
    private func launch(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Restart / shut down / log out without macOS's own dialog (the launcher already asked):
    /// `kCoreEventClass` events to loginwindow, kAERestart 'rest', kAEShutDown 'shut',
    /// kAEReallyLogOut 'rlgo' ('rrst' would be kAEShowRestartDialog).
    private func sendLoginWindowEvent(_ eventID: String) -> String? {
        sendAppleEvent(bundleIdentifier: "com.apple.loginwindow", eventClass: "aevt", eventID: eventID)
    }

    /// Finder's `empty trash`, not waiting for Finder to finish (a big Trash takes long).
    private func emptyTrash() -> String? {
        runAppleScript("""
        ignoring application responses
            tell application "Finder" to empty trash
        end ignoring
        """)
    }

    /// Unmounts and ejects every ejectable or removable volume (disk images, USB, SD).
    private func ejectAllDisks() -> String? {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeLocalizedNameKey]
        let volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .filter { url in
                guard url.path != "/", let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
                return values.volumeIsEjectable == true || values.volumeIsRemovable == true
            }
        guard !volumes.isEmpty else { return "No disks to eject" }

        var failures: [String] = []
        for volume in volumes {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            } catch {
                let name = (try? volume.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
                    ?? volume.lastPathComponent
                failures.append(name)
            }
        }
        guard !failures.isEmpty else { return nil }
        return "Couldn't eject \(failures.joined(separator: ", "))"
    }

    private func toggleSystemAppearance() -> String? {
        runAppleScript("""
        tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
        """)
    }

    /// Asks every regular app except Finder and Soprano Cast to quit (apps may still ask to
    /// save documents).
    private func quitAllApplications() -> String? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.bundleIdentifier != Self.finderBundleID && app.processIdentifier != ownPID {
            app.terminate()
        }
        return nil
    }

    /// Hides every regular app except the frontmost one (the launcher panel never activates
    /// Soprano Cast, so the frontmost app is the one the user was in).
    private func hideOtherApplications() -> String? {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != frontPID && app.processIdentifier != ownPID && !app.isHidden {
            app.hide()
        }
        return nil
    }

    /// Flips Finder's `AppleShowAllFiles` with `defaults write`, then quits Finder and opens
    /// it again in the background so it reads the new value.
    private func toggleHiddenFiles() -> String? {
        let showsAll = UserDefaults(suiteName: Self.finderBundleID)?.bool(forKey: "AppleShowAllFiles") ?? false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", Self.finderBundleID, "AppleShowAllFiles", "-bool", showsAll ? "false" : "true"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            guard finished.terminationStatus == 0 else { return }
            Task { @MainActor in
                await SystemCommandRunner.relaunchFinder()
            }
        }
        do {
            try process.run()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Helpers

    private static let finderBundleID = "com.apple.finder"

    /// Quits Finder, waits up to 5 s for it to exit, then opens it without activating it
    /// (a no-op when the system already relaunched it).
    private static func relaunchFinder() async {
        let finders = NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID)
        guard !finders.isEmpty else { return }
        for finder in finders { finder.terminate() }
        var waited = 0
        while finders.contains(where: { !$0.isTerminated }), waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    private static func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// Sends an event without a parameter, not waiting for the reply.
    private func sendAppleEvent(bundleIdentifier: String, eventClass: String, eventID: String) -> String? {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: Self.fourCharCode(eventClass),
            eventID: Self.fourCharCode(eventID),
            targetDescriptor: target,
            returnID: AEReturnID(-1),         // kAutoGenerateReturnID
            transactionID: AETransactionID(0) // kAnyTransactionID
        )
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 5)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Runs a short AppleScript on the main thread (NSAppleScript is main-thread only).
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return "Couldn't compile the AppleScript" }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return nil }
        if errorInfo[NSAppleScript.errorNumber] as? Int == -1743 {
            return "Soprano Cast needs Automation access (System Settings › Privacy & Security › Automation)"
        }
        return errorInfo[NSAppleScript.errorMessage] as? String ?? "The Apple event failed"
    }
}
