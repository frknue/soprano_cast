import AppKit
import SopranoCastCore

/// The fixture apps and script commands the snapshot harness and the tests search.
/// Ids, titles and folders are the real ones, so settings written against a real Mac
/// (`hotkeys`, `aliases`, `favorites`) apply to the fixtures unchanged.
@MainActor
final class FixtureCatalog: ItemSource {
    /// One fixture application.
    struct App {
        var bundleID: String
        var title: String
        /// The folder holding the bundle (the item's subtitle).
        var folder: String
        var keywords: [String] = []

        var path: String { "\(folder)/\(title).app" }
        var id: ItemID { ItemID(kind: .application, key: bundleID) }
    }

    /// One fixture script command and the output `FixtureRunner` pretends it printed.
    struct Script {
        var command: ScriptCommand
        var output: String

        var id: ItemID { ItemID(kind: .script, key: command.path) }
    }

    static let apps: [App] = [
        App(bundleID: "com.google.Chrome", title: "Google Chrome", folder: "/Applications", keywords: ["chrome"]),
        App(bundleID: "com.apple.Safari", title: "Safari", folder: "/Applications"),
        App(bundleID: "com.soprano.app", title: "Soprano", folder: "/Applications"),
        App(bundleID: "com.soprano.git", title: "Soprano Git", folder: "/Applications"),
        App(bundleID: "com.soprano.tab", title: "Soprano Tab", folder: "/Applications"),
        App(bundleID: "com.tinyspeck.slackmacgap", title: "Slack", folder: "/Applications"),
        App(bundleID: "com.apple.mail", title: "Mail", folder: "/System/Applications"),
        App(bundleID: "com.apple.Notes", title: "Notes", folder: "/System/Applications"),
        App(bundleID: "com.apple.Music", title: "Music", folder: "/System/Applications"),
        App(bundleID: "com.apple.finder", title: "Finder", folder: "/System/Library/CoreServices"),
        App(
            bundleID: "com.apple.systempreferences",
            title: "System Settings",
            folder: "/System/Applications",
            keywords: ["System Preferences"]
        ),
        App(bundleID: "com.apple.dt.Xcode", title: "Xcode", folder: "/Applications"),
        App(bundleID: "at.studio.AsideBrowser", title: "Aside", folder: "/Applications"),
        App(bundleID: "net.whatsapp.WhatsApp", title: "WhatsApp", folder: "/Applications"),
    ]

    /// A silent script, a compact one with a required argument, and a fullOutput one.
    static let scripts: [Script] = [
        Script(
            command: ScriptCommand(
                path: "/fixtures/scripts/caffeinate.sh",
                title: "Keep Awake",
                mode: .silent,
                packageName: "Utilities",
                icon: .emoji("☕️"),
                description: "Prevents sleep for an hour"
            ),
            output: "Staying awake for 60 minutes"
        ),
        Script(
            command: ScriptCommand(
                path: "/fixtures/scripts/search-issues.sh",
                title: "Search Issues",
                mode: .compact,
                packageName: "GitHub",
                icon: .emoji("🐙"),
                arguments: [ArgumentSpec(name: "query", placeholder: "Query")]
            ),
            output: "Opened 3 matching issues"
        ),
        Script(
            command: ScriptCommand(
                path: "/fixtures/scripts/disk-usage.sh",
                title: "Disk Usage",
                mode: .fullOutput,
                packageName: "System",
                icon: .emoji("💾")
            ),
            output: """
            Filesystem      Size   Used  Avail Capacity  Mounted on
            /dev/disk3s1s1  926Gi  412Gi  471Gi    47%    /
            /dev/disk3s5    926Gi  398Gi  471Gi    46%    /System/Volumes/Data
            """
        ),
    ]

    /// Apps `FixtureRunner.isRunning` reports as running (the Action Panel offers Quit/Hide).
    static let runningBundleIDs: Set<String> = [
        "com.google.Chrome", "com.soprano.app", "com.tinyspeck.slackmacgap", "com.apple.finder",
    ]

    static func script(for id: ItemID) -> Script? {
        scripts.first { $0.id == id }
    }

    let items: [CastItem]
    var onChange: (() -> Void)?

    init() {
        let appItems = Self.apps.map { app in
            CastItem(
                id: app.id,
                title: app.title,
                subtitle: app.folder,
                keywords: app.keywords,
                icon: .file(path: app.path)
            )
        }
        let scriptItems = Self.scripts.map { script in
            CastItem(
                id: script.id,
                title: script.command.title,
                subtitle: script.command.packageName,
                icon: script.command.icon ?? .glyph(.script),
                arguments: script.command.arguments,
                needsConfirmation: script.command.needsConfirmation
            )
        }
        items = appItems + scriptItems
    }

    /// The fixture list is fixed: there is nothing to watch, so `onChange` never fires.
    func start() {}

    func stop() {}
}
