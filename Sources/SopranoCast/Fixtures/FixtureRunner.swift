import AppKit
import SopranoCastCore

/// Records every run and action instead of doing it. Items close the launcher; fixture
/// scripts return their mode's outcome with the output `FixtureCatalog` gives them.
@MainActor
final class FixtureRunner: ItemRunning {
    /// "run app:com.google.Chrome", "run script:/fixtures/scripts/search-issues.sh \"bug\"",
    /// "perform copyPath app:com.google.Chrome", in call order.
    private(set) var log: [String] = []

    init() {}

    func run(_ item: CastItem, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void) {
        log.append((["run \(item.id.rawValue)"] + arguments.map { "\"\($0)\"" }).joined(separator: " "))
        completion(Self.outcome(for: item))
    }

    func perform(_ action: ItemActionID, on item: CastItem) -> RunOutcome {
        log.append("perform \(action.rawValue) \(item.id.rawValue)")
        return .done(closeLauncher: true)
    }

    func isRunning(_ item: CastItem) -> Bool {
        item.kind == .application && FixtureCatalog.runningBundleIDs.contains(item.id.key)
    }

    /// Scripts end like `ScriptRunner` presents a successful run of their mode; everything
    /// else is done and closes the launcher.
    private static func outcome(for item: CastItem) -> RunOutcome {
        guard let script = FixtureCatalog.script(for: item.id) else { return .done(closeLauncher: true) }
        let lastLine = ScriptOutput.lastLine(script.output)
        switch script.command.mode {
        case .silent: return .hud(lastLine ?? script.command.title)
        case .compact, .inline: return .toast(lastLine ?? script.command.title, isError: false)
        case .fullOutput: return .output(title: script.command.title, text: script.output, isError: false)
        }
    }
}
