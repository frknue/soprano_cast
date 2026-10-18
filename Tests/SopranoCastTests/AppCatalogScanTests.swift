import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

struct AppCatalogScanTests {
    /// Computed: a stored `[String: Any]` static is not concurrency-safe.
    private static var chromePlist: [String: Any] {
        [
            "CFBundleIdentifier": "com.google.Chrome",
            "CFBundleName": "Chrome",
            "CFBundleExecutable": "Google Chrome",
        ]
    }

    private func item(_ bundleID: String, title: String, path: String) -> (CastItem, path: String) {
        let item = CastItem(id: ItemID(kind: .application, key: bundleID), title: title, icon: .file(path: path))
        return (item, path: path)
    }

    // MARK: - entry(forBundleAt:infoPlist:)

    @Test("An app is listed under its bundle id with its folder, keywords and file icon")
    func entryFromInfoPlist() throws {
        let path = "/Volumes/NoSuchDisk/Apps/Google Chrome.app"
        let entry = try #require(LiveAppCatalog.entry(forBundleAt: URL(fileURLWithPath: path), infoPlist: Self.chromePlist))
        #expect(entry.id == ItemID(rawValue: "app:com.google.Chrome"))
        #expect(entry.title == "Google Chrome")
        #expect(entry.subtitle == "/Volumes/NoSuchDisk/Apps")
        #expect(entry.keywords == ["Chrome"])
        #expect(entry.icon == .file(path: path))
    }

    @Test("A bundle without a bundle id is listed under its path")
    func entryWithoutBundleID() throws {
        let path = "/Volumes/NoSuchDisk/Apps/Tool.app"
        let plist: [String: Any] = ["CFBundleExecutable": "tool-cli"]
        let entry = try #require(LiveAppCatalog.entry(forBundleAt: URL(fileURLWithPath: path), infoPlist: plist))
        #expect(entry.id == ItemID(rawValue: "app:\(path)"))
        #expect(entry.title == "Tool")
        #expect(entry.keywords == ["tool-cli"])
    }

    @Test("A blank bundle id counts as missing")
    func entryWithBlankBundleID() throws {
        let path = "/Volumes/NoSuchDisk/Apps/Blank.app"
        let entry = try #require(LiveAppCatalog.entry(forBundleAt: URL(fileURLWithPath: path), infoPlist: ["CFBundleIdentifier": "  "]))
        #expect(entry.id.key == path)
    }

    @Test("Background-only apps are skipped, whatever type the flag has")
    func backgroundOnlySkipped() {
        let url = URL(fileURLWithPath: "/Volumes/NoSuchDisk/Apps/Agent.app")
        let backgroundFlags: [Any] = [true, NSNumber(value: 1), "YES", "1"]
        for flag in backgroundFlags {
            var plist = Self.chromePlist
            plist["LSBackgroundOnly"] = flag
            #expect(LiveAppCatalog.entry(forBundleAt: url, infoPlist: plist) == nil)
        }
        let foregroundFlags: [Any] = [false, NSNumber(value: 0), "NO"]
        for flag in foregroundFlags {
            var plist = Self.chromePlist
            plist["LSBackgroundOnly"] = flag
            #expect(LiveAppCatalog.entry(forBundleAt: url, infoPlist: plist) != nil)
        }
    }

    @Test("Apps inside other bundles produce no entry")
    func nestedEntrySkipped() {
        let url = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
        #expect(LiveAppCatalog.entry(forBundleAt: url, infoPlist: ["CFBundleIdentifier": "com.apple.iphonesimulator"]) == nil)
    }

    @Test("Keywords leave out values equal to the title and duplicates")
    func keywordsDeduplicated() throws {
        let url = URL(fileURLWithPath: "/Volumes/NoSuchDisk/Apps/Slack.app")
        let plist: [String: Any] = ["CFBundleIdentifier": "com.tinyspeck.slackmacgap", "CFBundleName": "slack", "CFBundleExecutable": "Slack"]
        let entry = try #require(LiveAppCatalog.entry(forBundleAt: url, infoPlist: plist))
        #expect(entry.keywords.isEmpty)
    }

    @Test("The folder subtitle abbreviates the home folder to ~")
    func subtitleAbbreviatesHome() throws {
        let path = NSHomeDirectory() + "/Applications/NoSuchApp.app"
        let entry = try #require(LiveAppCatalog.entry(forBundleAt: URL(fileURLWithPath: path), infoPlist: Self.chromePlist))
        #expect(entry.subtitle == "~/Applications")
    }

    // MARK: - isNested

    @Test("Nested detection looks at ancestor bundles only")
    func nestedDetection() {
        #expect(LiveAppCatalog.isNested("/Applications/Xcode.app/Contents/Applications/Instruments.app"))
        #expect(LiveAppCatalog.isNested("/Library/Frameworks/Foo.framework/Versions/A/Helper.app"))
        #expect(LiveAppCatalog.isNested("/Applications/Foo.APP/Contents/Helper.app/"))
        #expect(!LiveAppCatalog.isNested("/Applications/Safari.app"))
        #expect(!LiveAppCatalog.isNested("/Applications/Safari.app/"))
        #expect(!LiveAppCatalog.isNested("/Applications/Utilities/Terminal.app"))
        #expect(!LiveAppCatalog.isNested("/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app"))
    }

    // MARK: - deduplicated

    @Test("/Applications wins over every other copy of a bundle id")
    func applicationsPreferred() {
        let items = LiveAppCatalog.deduplicated([
            item("com.example.a", title: "A", path: "/System/Applications/A.app"),
            item("com.example.a", title: "A", path: "/Users/me/Applications/A.app"),
            item("com.example.a", title: "A", path: "/Applications/Long Folder Name/A.app"),
            item("com.example.a", title: "A", path: "/B/A.app"),
        ])
        #expect(items.count == 1)
        #expect(items.first?.icon == .file(path: "/Applications/Long Folder Name/A.app"))
    }

    @Test("/System/Applications wins over other folders")
    func systemApplicationsPreferred() {
        let items = LiveAppCatalog.deduplicated([
            item("com.apple.Notes", title: "Notes", path: "/Volumes/X/Notes.app"),
            item("com.apple.Notes", title: "Notes", path: "/System/Applications/Notes.app"),
        ])
        #expect(items.map { $0.icon } == [.file(path: "/System/Applications/Notes.app")])
    }

    @Test("Elsewhere the shortest path wins, regardless of order")
    func shortestPathPreferred() {
        let long = item("com.example.tool", title: "Tool", path: "/Users/me/Downloads/Old/Tool.app")
        let short = item("com.example.tool", title: "Tool", path: "/Users/me/Tool.app")
        #expect(LiveAppCatalog.deduplicated([long, short]).map { $0.icon } == [.file(path: "/Users/me/Tool.app")])
        #expect(LiveAppCatalog.deduplicated([short, long]).map { $0.icon } == [.file(path: "/Users/me/Tool.app")])
    }

    @Test("Different bundle ids all stay, sorted by title")
    func distinctIDsKeptSorted() {
        let items = LiveAppCatalog.deduplicated([
            item("com.example.zed", title: "Zed", path: "/Applications/Zed.app"),
            item("com.example.app2", title: "App 10", path: "/Applications/App 10.app"),
            item("com.example.app1", title: "App 9", path: "/Applications/App 9.app"),
        ])
        #expect(items.map { $0.title } == ["App 9", "App 10", "Zed"])
    }
}
