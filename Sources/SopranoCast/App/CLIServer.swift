import AppKit
import OSLog
import SopranoCastCore

private let cliLog = Logger(subsystem: "com.soprano.cast", category: "cli")

/// What the CLI drives in the running app: `LauncherController`, or a stub in tests.
@MainActor
protocol CLIControlling: AnyObject {
    var allItems: [CastItem] { get }
    func toggle()
    func run(itemID: ItemID, arguments: [String])
}

extension LauncherController: CLIControlling {}

/// Answers `SopranoCast <command>` from the running app: a local `CFMessagePort` named
/// `<bundle id>.cli` on the main run loop, JSON `CLIRequest` in, JSON `CLIResponse` out.
@MainActor
final class CLIServer {
    /// The port both sides use.
    nonisolated static var portName: String {
        "\(Bundle.main.bundleIdentifier ?? "com.soprano.cast").cli"
    }

    private let controller: CLIControlling
    private let settings: @MainActor () -> CastSettings
    private var port: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?

    init(controller: CLIControlling, settings: @escaping @MainActor () -> CastSettings = { SettingsCenter.shared.settings }) {
        self.controller = controller
        self.settings = settings
    }

    /// Opens the port. Logs and stays inert when the name is taken (another instance).
    func start() {
        guard port == nil else { return }
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        var shouldFreeInfo: DarwinBoolean = false
        let callback: CFMessagePortCallBack = { _, _, data, info in
            guard let info else { return nil }
            let request = data.map { $0 as Data }
            // Safe: the port's run loop source is on the main run loop, so assumeIsolated
            // holds and the pointer never crosses an isolation boundary.
            nonisolated(unsafe) let serverPointer = info
            let reply = MainActor.assumeIsolated {
                Unmanaged<CLIServer>.fromOpaque(serverPointer).takeUnretainedValue().reply(to: request)
            }
            return Unmanaged.passRetained(reply as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil, Self.portName as CFString, callback, &context, &shouldFreeInfo) else {
            cliLog.error("Could not open the CLI port \(Self.portName, privacy: .public)")
            return
        }
        let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.port = port
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let port {
            CFMessagePortInvalidate(port)
        }
        runLoopSource = nil
        port = nil
    }

    private func reply(to data: Data?) -> Data {
        let response: CLIResponse
        if let data, let request = try? JSONDecoder().decode(CLIRequest.self, from: data) {
            response = Self.response(for: request, controller: controller, settings: settings())
        } else {
            response = CLIResponse(ok: false, error: "Bad request.")
        }
        return (try? Self.encoder.encode(response)) ?? Data()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// The answer to one request. `toggle` toggles the launcher; `open` runs an item Root
    /// Search knows as its hotkey would (disabled items included; hotkeys run them too);
    /// `list` returns every item, sorted by title, with its hotkey, alias, favorite and
    /// disabled state from `settings`.
    static func response(for request: CLIRequest, controller: CLIControlling, settings: CastSettings) -> CLIResponse {
        switch request {
        case .toggleLauncher:
            controller.toggle()
            return CLIResponse(ok: true)
        case .open(let rawID, let arguments):
            let id = ItemID(rawValue: rawID)
            guard id.kind != nil else {
                return CLIResponse(ok: false, error: "Unknown item id \(rawID); ids look like app:com.google.Chrome")
            }
            guard controller.allItems.contains(where: { $0.id == id }) else {
                return CLIResponse(ok: false, error: "No item \(rawID)")
            }
            controller.run(itemID: id, arguments: arguments)
            return CLIResponse(ok: true)
        case .list:
            let favorites = Set(settings.favorites)
            let items = controller.allItems
                .sorted { lhs, rhs in
                    let order = lhs.title.localizedStandardCompare(rhs.title)
                    if order != .orderedSame { return order == .orderedAscending }
                    return lhs.id < rhs.id
                }
                .map { item in
                    CLIItem(
                        id: item.id.rawValue,
                        title: item.title,
                        kind: item.kind?.rawValue ?? "",
                        subtitle: item.subtitle,
                        hotkey: settings.hotkeys[item.id]?.settingsText,
                        alias: settings.aliases[item.id],
                        favorite: favorites.contains(item.id),
                        disabled: settings.disabled.contains(item.id)
                    )
                }
            return CLIResponse(ok: true, items: items)
        }
    }
}
