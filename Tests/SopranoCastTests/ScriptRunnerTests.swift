import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct ScriptRunnerTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a bash script and returns its path; `executable` sets mode 755, else 644.
    private func writeScript(
        _ body: String,
        named name: String = "script.sh",
        in folder: URL,
        executable: Bool = true,
        firstLine: String = "#!/bin/bash"
    ) throws -> String {
        let url = folder.appendingPathComponent(name)
        try (firstLine + "\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url.path
    }

    private func script(_ path: String, mode: ScriptCommand.Mode, currentDirectoryPath: String? = nil) -> ScriptCommand {
        ScriptCommand(path: path, title: "Test Script", mode: mode, packageName: "Tests", currentDirectoryPath: currentDirectoryPath)
    }

    private func outcome(of script: ScriptCommand, arguments: [String] = []) async -> RunOutcome {
        let runner = ScriptRunner()
        return await withCheckedContinuation { continuation in
            runner.run(script, arguments: arguments) { continuation.resume(returning: $0) }
        }
    }

    /// The path with every symlink resolved (/var → /private/var), as `pwd -P` prints it.
    private func physicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    @Test("silent mode shows the last output line as a HUD")
    func silentModeShowsHUD() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo first\necho second", in: folder)

        #expect(await outcome(of: script(path, mode: .silent)) == .hud("second"))
    }

    @Test("silent mode without output shows the title")
    func silentModeWithoutOutputShowsTitle() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("true", in: folder)

        #expect(await outcome(of: script(path, mode: .silent)) == .hud("Test Script"))
    }

    @Test("compact mode shows the last output line as a footer toast")
    func compactModeShowsToast() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo working\necho Done", in: folder)

        #expect(await outcome(of: script(path, mode: .compact)) == .toast("Done", isError: false))
    }

    @Test("inline mode shows the last output line as a footer toast")
    func inlineModeShowsToast() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo 42 °C", in: folder)

        #expect(await outcome(of: script(path, mode: .inline)) == .toast("42 °C", isError: false))
    }

    @Test("full output mode shows stdout and stderr merged in the order written")
    func fullOutputMergesStreamsInOrder() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo one\necho two >&2\necho three", in: folder)

        #expect(await outcome(of: script(path, mode: .fullOutput)) == .output(title: "Test Script", text: "one\ntwo\nthree\n", isError: false))
    }

    @Test("ANSI color codes are stripped from the output")
    func ansiCodesAreStripped() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript(#"printf '\033[1;32mgreen\033[0m plain\n'"#, in: folder)

        #expect(await outcome(of: script(path, mode: .fullOutput)) == .output(title: "Test Script", text: "green plain\n", isError: false))
        #expect(await outcome(of: script(path, mode: .compact)) == .toast("green plain", isError: false))
    }

    @Test("a non-zero exit shows the last line as an error toast")
    func failureShowsErrorToast() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo 'No network' >&2\nexit 3", in: folder)

        #expect(await outcome(of: script(path, mode: .silent)) == .toast("No network", isError: true))
        #expect(await outcome(of: script(path, mode: .compact)) == .toast("No network", isError: true))
        #expect(await outcome(of: script(path, mode: .inline)) == .toast("No network", isError: true))
    }

    @Test("a non-zero exit without output shows that the script failed")
    func silentFailureSaysScriptFailed() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("exit 1", in: folder)

        #expect(await outcome(of: script(path, mode: .compact)) == .toast("Script failed", isError: true))
    }

    @Test("a non-zero exit in full output mode shows the output as an error")
    func fullOutputFailureIsAnErrorOutput() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo partial\necho 'bad input' >&2\nexit 2", in: folder)

        #expect(await outcome(of: script(path, mode: .fullOutput)) == .output(title: "Test Script", text: "partial\nbad input\n", isError: true))
    }

    @Test("arguments reach the script positionally, spaces intact")
    func argumentsArePositional() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript(#"echo "$#:$1|$2|$3""#, in: folder)

        let result = await outcome(of: script(path, mode: .compact), arguments: ["hello world", "", "3"])
        #expect(result == .toast("3:hello world||3", isError: false))
    }

    @Test("a file without the executable bit runs through its shebang interpreter")
    func nonExecutableRunsThroughShebang() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript(#"echo "via $1""#, in: folder, executable: false)

        #expect(!FileManager.default.isExecutableFile(atPath: path))
        #expect(await outcome(of: script(path, mode: .compact), arguments: ["shebang"]) == .toast("via shebang", isError: false))
    }

    @Test("a shebang through /usr/bin/env runs the script with its path as $0")
    func envShebangRuns() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo \"$0\"", in: folder, executable: false, firstLine: "#!/usr/bin/env bash")

        #expect(await outcome(of: script(path, mode: .compact)) == .toast(path, isError: false))
    }

    @Test("a file that is neither executable nor has a shebang fails with an error toast")
    func noShebangFails() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("echo never", in: folder, executable: false, firstLine: "# plain text")

        let result = await outcome(of: script(path, mode: .compact))
        #expect(result == .toast("Script is not executable and has no #! line", isError: true))
    }

    @Test("a missing script fails with an error, as output in full output mode")
    func missingScriptFails() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("gone.sh").path

        let compact = await outcome(of: script(path, mode: .compact))
        let full = await outcome(of: script(path, mode: .fullOutput))
        guard case .toast(_, let compactIsError) = compact, case .output(_, _, let fullIsError) = full else {
            Issue.record("unexpected outcomes \(compact), \(full)")
            return
        }
        #expect(compactIsError)
        #expect(fullIsError)
    }

    @Test("the working directory is the script's folder by default")
    func workingDirectoryDefaultsToScriptFolder() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("pwd -P", in: folder)

        #expect(await outcome(of: script(path, mode: .compact)) == .toast(physicalPath(folder.path), isError: false))
    }

    @Test("currentDirectoryPath sets the working directory, relative to the script's folder")
    func currentDirectoryPathIsHonored() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sub = folder.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let path = try writeScript("pwd -P", in: folder)

        #expect(await outcome(of: script(path, mode: .compact, currentDirectoryPath: "work")) == .toast(physicalPath(sub.path), isError: false))
        #expect(await outcome(of: script(path, mode: .compact, currentDirectoryPath: sub.path)) == .toast(physicalPath(sub.path), isError: false))
    }

    @Test("PATH starts with the Homebrew folders")
    func pathHasHomebrewPrefix() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript(#"echo "$PATH""#, in: folder)

        let result = await outcome(of: script(path, mode: .compact))
        guard case .toast(let text, false) = result else {
            Issue.record("unexpected outcome \(result)")
            return
        }
        #expect(text.hasPrefix("/opt/homebrew/bin:/usr/local/bin:"))
        #expect(text.count > "/opt/homebrew/bin:/usr/local/bin:".count)
    }

    @Test("run returns at once while the script keeps running in the background")
    func runDoesNotBlock() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = try writeScript("sleep 0.5\necho late", in: folder)
        let runner = ScriptRunner()
        let clock = ContinuousClock()
        var returnedAfter: Duration = .zero

        let result: RunOutcome = await withCheckedContinuation { continuation in
            let start = clock.now
            runner.run(script(path, mode: .compact), arguments: []) { continuation.resume(returning: $0) }
            returnedAfter = clock.now - start
        }

        #expect(returnedAfter < .milliseconds(200))
        #expect(result == .toast("late", isError: false))
    }
}
