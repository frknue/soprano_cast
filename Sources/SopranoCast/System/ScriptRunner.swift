import AppKit
import SopranoCastCore

/// Runs Raycast-format script commands. Each run is a `Process` on a background queue, so a
/// slow or hanging script never blocks the main thread; results come back on the main actor.
@MainActor
final class ScriptRunner {
    init() {}

    /// Runs `script` with positional `arguments` and reports the outcome its mode asks for.
    func run(_ script: ScriptCommand, arguments: [String], completion: @escaping @MainActor (RunOutcome) -> Void) {
        execute(script, arguments: arguments) { execution in
            completion(Self.outcome(for: script, execution: execution))
        }
    }

    /// Runs `script` and hands back the raw result (the catalog reads inline output from it).
    func execute(_ script: ScriptCommand, arguments: [String], completion: @escaping @MainActor (ScriptExecution) -> Void) {
        let invocation = ScriptInvocation(script: script, arguments: arguments)
        Task {
            let execution = await invocation.executeInBackground()
            completion(execution)
        }
    }

    /// The launcher outcome for a finished run, by mode:
    /// silent → HUD, compact and inline → footer toast (the last output line, else the
    /// title), fullOutput → the output view. A failed run (non-zero exit, killed, or not
    /// launchable) → an error toast with the last line, or the error output view.
    nonisolated static func outcome(for script: ScriptCommand, execution: ScriptExecution) -> RunOutcome {
        let text = ScriptOutput.strippingANSI(execution.output)
        let lastLine = ScriptOutput.lastLine(execution.output)

        if let launchError = execution.launchError {
            if script.mode == .fullOutput {
                return .output(title: script.title, text: launchError, isError: true)
            }
            return .toast(launchError, isError: true)
        }
        guard execution.succeeded else {
            if script.mode == .fullOutput {
                return .output(title: script.title, text: text, isError: true)
            }
            return .toast(lastLine ?? "Script failed", isError: true)
        }
        switch script.mode {
        case .silent: return .hud(lastLine ?? script.title)
        case .compact, .inline: return .toast(lastLine ?? script.title, isError: false)
        case .fullOutput: return .output(title: script.title, text: text, isError: false)
        }
    }
}

/// What one script run produced.
struct ScriptExecution: Equatable, Sendable {
    /// stdout and stderr merged in the order the script wrote them (raw, ANSI included).
    var output: String
    /// The exit status, or the signal number when `terminatedBySignal`.
    var status: Int32
    var terminatedBySignal: Bool
    /// Why the script could not be started; nil when it ran.
    var launchError: String?

    var succeeded: Bool { launchError == nil && !terminatedBySignal && status == 0 }
}

/// How to start one script: the executable, its argument vector, cwd and environment.
/// Built on the main actor, executed on a background queue.
struct ScriptInvocation: Sendable {
    /// Prepended to the inherited PATH: GUI apps start with launchd's minimal PATH, and
    /// scripts expect Homebrew's tools.
    static let pathPrefix = "/opt/homebrew/bin:/usr/local/bin:"

    var scriptPath: String
    var arguments: [String]
    var currentDirectoryPath: String

    init(script: ScriptCommand, arguments: [String]) {
        scriptPath = script.path
        self.arguments = arguments
        currentDirectoryPath = Self.workingDirectory(for: script)
    }

    /// `currentDirectoryPath` (~ expanded; relative paths resolve against the script's
    /// folder), else the script's folder.
    static func workingDirectory(for script: ScriptCommand) -> String {
        let folder = (script.path as NSString).deletingLastPathComponent
        guard let path = script.currentDirectoryPath?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return folder
        }
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return (expanded as NSString).standardizingPath }
        return ((folder as NSString).appendingPathComponent(expanded) as NSString).standardizingPath
    }

    /// The inherited environment with `pathPrefix` in front of PATH.
    static func environment(inherited: [String: String]) -> [String: String] {
        var environment = inherited
        let path = inherited["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = pathPrefix + path
        return environment
    }

    /// The interpreter and its arguments from a `#!` first line; nil without one.
    static func shebang(in firstLine: String) -> [String]? {
        guard firstLine.hasPrefix("#!") else { return nil }
        let words = firstLine.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return words.isEmpty ? nil : words
    }

    /// Executable files run directly; others through their shebang interpreter (with the
    /// shebang's own arguments), the script path, then the positional arguments.
    func command() -> (executable: String, arguments: [String])? {
        if FileManager.default.isExecutableFile(atPath: scriptPath) {
            return (scriptPath, arguments)
        }
        guard let handle = FileHandle(forReadingAtPath: scriptPath) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1024)) ?? Data()
        let firstLine = String(decoding: head, as: UTF8.self)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard let interpreter = Self.shebang(in: firstLine) else { return nil }
        return (interpreter[0], Array(interpreter.dropFirst()) + [scriptPath] + arguments)
    }

    /// Runs the script on a background queue and resumes with its result.
    func executeInBackground() async -> ScriptExecution {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: executeBlocking())
            }
        }
    }

    /// Runs the script to completion on the calling thread. Never call on the main thread.
    func executeBlocking() -> ScriptExecution {
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return Self.failure("Script not found: \((scriptPath as NSString).abbreviatingWithTildeInPath)")
        }
        guard let command = command() else {
            return Self.failure("Script is not executable and has no #! line")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        process.environment = Self.environment(inherited: ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        // One pipe for both streams keeps their interleaving as the script wrote it.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return Self.failure(error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptExecution(
            output: String(decoding: data, as: UTF8.self),
            status: process.terminationStatus,
            terminatedBySignal: process.terminationReason == .uncaughtSignal,
            launchError: nil
        )
    }

    private static func failure(_ message: String) -> ScriptExecution {
        ScriptExecution(output: "", status: -1, terminatedBySignal: false, launchError: message)
    }
}
