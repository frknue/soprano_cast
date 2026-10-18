import AppKit
import ApplicationServices

/// The privacy grant Soprano Cast uses.
struct PermissionStatus: Equatable {
    /// Window management, modifier-only hotkeys, fn hotkeys and the Hyper key. App,
    /// quicklink and script hotkeys work without it.
    var accessibility: Bool

    var allGranted: Bool { accessibility }
}

/// Reads and requests the privacy grant.
@MainActor
enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static var status: PermissionStatus {
        PermissionStatus(accessibility: isAccessibilityTrusted)
    }

    /// Shows macOS's Accessibility prompt (once per call while not trusted), which also adds
    /// the app to the list in System Settings.
    static func requestAccessibility() {
        // The value of `kAXTrustedCheckOptionPrompt`: the imported global is a mutable C
        // variable, which Swift 6 rejects as not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
