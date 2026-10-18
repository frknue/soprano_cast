import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct CLIRoundTripTests {
    /// Records what the CLI asked the launcher to do.
    @MainActor
    private final class StubController: CLIControlling {
        struct Run: Equatable {
            var id: ItemID
            var arguments: [String]
        }

        var allItems: [CastItem]
        private(set) var toggles = 0
        private(set) var runs: [Run] = []

        init(items: [CastItem]) {
            allItems = items
        }

        func toggle() {
            toggles += 1
        }

        func run(itemID: ItemID, arguments: [String]) {
            runs.append(Run(id: itemID, arguments: arguments))
        }
    }

    private let chrome = CastItem(
        id: ItemID(rawValue: "app:com.google.Chrome"),
        title: "Google Chrome",
        subtitle: "/Applications",
        icon: .file(path: "/Applications/Google Chrome.app")
    )
    private let safari = CastItem(
        id: ItemID(rawValue: "app:com.apple.Safari"),
        title: "Safari",
        subtitle: "/Applications",
        icon: .file(path: "/Applications/Safari.app")
    )
    private let leftHalf = CastItem(
        id: ItemID(kind: .windowCommand, key: WindowCommand.leftHalf.rawValue),
        title: "Left Half",
        subtitle: "Window Management",
        icon: .glyph(.window)
    )
    private let searchGoogle = CastItem(
        id: ItemID(kind: .castCommand, key: CastCommand.searchGoogle.rawValue),
        title: "Search Google",
        icon: .glyph(.magnifier),
        arguments: [ArgumentSpec(name: "Query", placeholder: "Query")]
    )

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    @Test("every request survives encoding and decoding")
    func requestsRoundTrip() throws {
        let requests: [CLIRequest] = [
            .toggleLauncher,
            .open(itemID: "app:com.google.Chrome", arguments: []),
            .open(itemID: "cast:searchGoogle", arguments: ["swift testing", "ünïcode"]),
            .list,
        ]
        for request in requests {
            #expect(try roundTrip(request) == request)
        }
    }

    @Test("responses with items or an error survive encoding and decoding")
    func responsesRoundTrip() throws {
        let items = [
            CLIItem(id: "app:com.google.Chrome", title: "Google Chrome", kind: "application", subtitle: "/Applications", hotkey: "cmd+1", alias: "gc", favorite: true, disabled: false),
            CLIItem(id: "window:leftHalf", title: "Left Half", kind: "windowCommand", subtitle: "", hotkey: nil, alias: nil, favorite: false, disabled: true),
        ]
        let list = CLIResponse(ok: true, items: items)
        let failure = CLIResponse(ok: false, error: "No item app:nope")

        #expect(try roundTrip(list) == list)
        #expect(try roundTrip(failure) == failure)
    }

    @Test("command-line arguments map to requests, open keeping every argument in order")
    func argumentsMapToRequests() {
        #expect(CLIClient.request(from: ["toggle"]) == .toggleLauncher)
        #expect(CLIClient.request(from: ["list"]) == .list)
        #expect(CLIClient.request(from: ["open", "app:com.google.Chrome"]) == .open(itemID: "app:com.google.Chrome", arguments: []))
        #expect(
            CLIClient.request(from: ["open", "quicklink:github", "soprano", "main"])
                == .open(itemID: "quicklink:github", arguments: ["soprano", "main"])
        )
    }

    @Test("help and malformed arguments give no request")
    func malformedArgumentsAreRejected() {
        #expect(CLIClient.request(from: []) == nil)
        #expect(CLIClient.request(from: ["help"]) == nil)
        #expect(CLIClient.request(from: ["--help"]) == nil)
        #expect(CLIClient.request(from: ["open"]) == nil)
        #expect(CLIClient.request(from: ["open", ""]) == nil)
        #expect(CLIClient.request(from: ["toggle", "now"]) == nil)
        #expect(CLIClient.request(from: ["list", "--all"]) == nil)
        #expect(CLIClient.request(from: ["launch"]) == nil)
    }

    @Test("toggle toggles the launcher")
    func toggleTogglesLauncher() {
        let controller = StubController(items: [chrome])

        let response = CLIServer.response(for: .toggleLauncher, controller: controller, settings: .defaults)

        #expect(response == CLIResponse(ok: true))
        #expect(controller.toggles == 1)
        #expect(controller.runs.isEmpty)
    }

    @Test("open runs a known item with its arguments, disabled items included")
    func openRunsKnownItem() {
        let controller = StubController(items: [chrome, searchGoogle])
        var settings = CastSettings.defaults
        settings.disabled = [chrome.id]

        let plain = CLIServer.response(for: .open(itemID: chrome.id.rawValue, arguments: []), controller: controller, settings: settings)
        let withQuery = CLIServer.response(
            for: .open(itemID: searchGoogle.id.rawValue, arguments: ["swift testing"]),
            controller: controller,
            settings: settings
        )

        #expect(plain.ok)
        #expect(withQuery.ok)
        #expect(controller.runs == [
            StubController.Run(id: chrome.id, arguments: []),
            StubController.Run(id: searchGoogle.id, arguments: ["swift testing"]),
        ])
    }

    @Test("open fails without running for a malformed id or an item that does not exist")
    func openRejectsUnknownItems() {
        let controller = StubController(items: [chrome])

        let malformed = CLIServer.response(for: .open(itemID: "chrome", arguments: []), controller: controller, settings: .defaults)
        let missing = CLIServer.response(for: .open(itemID: "app:com.example.Missing", arguments: []), controller: controller, settings: .defaults)

        #expect(!malformed.ok)
        #expect(malformed.error?.contains("chrome") == true)
        #expect(missing == CLIResponse(ok: false, error: "No item app:com.example.Missing"))
        #expect(controller.runs.isEmpty)
    }

    @Test("list returns every item by title with its hotkey, alias, favorite and disabled state")
    func listCarriesSettings() throws {
        let controller = StubController(items: [safari, leftHalf, chrome])
        var settings = CastSettings.defaults
        settings.hotkeys = [chrome.id: .combo(HotkeyCombo(modifiers: .command, key: .character("1")))]
        settings.aliases = [chrome.id: "gc"]
        settings.favorites = [chrome.id]
        settings.disabled = [leftHalf.id]

        let response = CLIServer.response(for: .list, controller: controller, settings: settings)

        let items = try #require(response.items)
        #expect(response.ok)
        #expect(items.map { $0.title } == ["Google Chrome", "Left Half", "Safari"])
        #expect(items[0] == CLIItem(
            id: "app:com.google.Chrome",
            title: "Google Chrome",
            kind: "application",
            subtitle: "/Applications",
            hotkey: "cmd+1",
            alias: "gc",
            favorite: true,
            disabled: false
        ))
        #expect(items[1].kind == "windowCommand")
        #expect(items[1].disabled)
        #expect(!items[1].favorite)
        #expect(items[2].hotkey == nil)
        #expect(items[2].alias == nil)
        #expect(controller.runs.isEmpty)
        #expect(controller.toggles == 0)
    }
}
