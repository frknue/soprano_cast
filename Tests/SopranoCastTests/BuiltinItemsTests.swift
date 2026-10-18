import AppKit
import Testing
@testable import SopranoCastCore

struct BuiltinItemsTests {
    private func items(quicklinks: [Quicklink] = []) -> [CastItem] {
        var settings = CastSettings()
        settings.quicklinks = quicklinks
        return BuiltinItems.items(settings: settings)
    }

    private func item(_ id: String, in items: [CastItem]) -> CastItem? {
        items.first { $0.id.rawValue == id }
    }

    @Test("every system, window and Soprano Cast command is listed once with a unique id")
    func everyCommand() {
        let all = items()
        #expect(all.count == SystemCommand.allCases.count + WindowCommand.allCases.count + CastCommand.allCases.count)
        #expect(Set(all.map { $0.id }).count == all.count)
        for command in SystemCommand.allCases {
            #expect(item("system:\(command.rawValue)", in: all)?.title == command.title)
        }
        for command in WindowCommand.allCases {
            #expect(item("window:\(command.rawValue)", in: all)?.title == command.title)
        }
        for command in CastCommand.allCases {
            #expect(item("cast:\(command.rawValue)", in: all)?.title == command.title)
        }
    }

    @Test("subtitles name the command group and icons are the command glyphs")
    func subtitlesAndIcons() {
        let all = items()
        let lock = item("system:lockScreen", in: all)
        #expect(lock?.subtitle == "System")
        #expect(lock?.icon == .glyph(.lock))
        let half = item("window:leftHalf", in: all)
        #expect(half?.subtitle == "Window Management")
        #expect(half?.icon == .glyph(.window))
        let settings = item("cast:openSettings", in: all)
        #expect(settings?.subtitle == "Soprano Cast")
        #expect(settings?.icon == .glyph(.gear))
        #expect(all.filter { $0.kind == .windowCommand }.allSatisfy { $0.icon == .glyph(.window) })
    }

    @Test("commands carry Raycast-like search keywords")
    func keywords() {
        let all = items()
        #expect(item("system:toggleSystemAppearance", in: all)?.keywords.contains("dark mode") == true)
        #expect(item("system:emptyTrash", in: all)?.keywords.contains("trash") == true)
        #expect(item("system:ejectAllDisks", in: all)?.keywords.contains("eject") == true)
        #expect(item("system:lockScreen", in: all)?.keywords.contains("lock") == true)
        #expect(item("window:toggleFullscreen", in: all)?.keywords.contains("fullscreen") == true)
        #expect(item("window:rightHalf", in: all)?.keywords.contains("half") == true)
        #expect(item("window:centerThird", in: all)?.keywords.contains("third") == true)
        #expect(item("window:nextDisplay", in: all)?.keywords.contains("monitor") == true)
        #expect(all.allSatisfy { !$0.keywords.isEmpty })
    }

    @Test("only the risky system commands ask for confirmation")
    func confirmation() {
        let all = items()
        let confirming = Set(all.filter { $0.needsConfirmation }.map { $0.id.rawValue })
        #expect(confirming == [
            "system:restart", "system:shutDown", "system:logOut", "system:emptyTrash", "system:quitAllApplications",
        ])
    }

    @Test("web searches take one required Query argument; other commands take none")
    func searchArguments() {
        let all = items()
        let query = [ArgumentSpec(name: "Query", placeholder: "Query")]
        #expect(item("cast:searchGoogle", in: all)?.arguments == query)
        #expect(item("cast:searchDuckDuckGo", in: all)?.arguments == query)
        #expect(all.filter { !$0.arguments.isEmpty }.count == 2)
    }

    @Test("each quicklink becomes an item with its link as subtitle and its template arguments")
    func quicklinks() {
        let links = [
            Quicklink(id: "gh", name: "GitHub Repo", link: "https://github.com/{argument name=\"repo\" default=\"apple\"}"),
            Quicklink(id: "notes", name: "Notes", link: "~/Notes"),
        ]
        let all = items(quicklinks: links)
        #expect(all.count == SystemCommand.allCases.count + WindowCommand.allCases.count + CastCommand.allCases.count + 2)
        let github = item("quicklink:gh", in: all)
        #expect(github?.title == "GitHub Repo")
        #expect(github?.subtitle == "https://github.com/{argument name=\"repo\" default=\"apple\"}")
        #expect(github?.arguments == [ArgumentSpec(name: "repo", placeholder: "repo", isOptional: true)])
        #expect(item("quicklink:notes", in: all)?.arguments == [])
        #expect(all.suffix(2).map { $0.id.rawValue } == ["quicklink:gh", "quicklink:notes"])
    }

    @Test("quicklink icons: emoji, image path, otherwise the link glyph")
    func quicklinkIcons() {
        let all = items(quicklinks: [
            Quicklink(id: "a", name: "A", link: "https://a.example", icon: "🚀"),
            Quicklink(id: "b", name: "B", link: "https://b.example", icon: "/Users/me/icons/b.png"),
            Quicklink(id: "c", name: "C", link: "https://c.example"),
            Quicklink(id: "d", name: "D", link: "https://d.example", icon: "rocket"),
            Quicklink(id: "e", name: "E", link: "https://e.example", icon: "👩‍💻"),
        ])
        #expect(item("quicklink:a", in: all)?.icon == .emoji("🚀"))
        #expect(item("quicklink:b", in: all)?.icon == .file(path: "/Users/me/icons/b.png"))
        #expect(item("quicklink:c", in: all)?.icon == .glyph(.link))
        #expect(item("quicklink:d", in: all)?.icon == .glyph(.link))
        #expect(item("quicklink:e", in: all)?.icon == .emoji("👩‍💻"))
    }
}
