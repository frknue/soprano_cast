import AppKit
import Testing
@testable import SopranoCastCore

struct ScriptMetadataParserTests {
    private let path = "/Users/me/scripts/tools/hello.sh"

    private func parse(_ contents: String) -> Result<ScriptCommand, ScriptParseError> {
        ScriptMetadataParser.parse(contents: contents, path: path, directoryName: "tools")
    }

    private func command(_ contents: String) -> ScriptCommand? {
        try? parse(contents).get()
    }

    private func error(_ contents: String) -> ScriptParseError? {
        if case .failure(let failure) = parse(contents) { failure } else { nil }
    }

    private func header(_ extra: String = "", mode: String = "silent") -> String {
        """
        #!/bin/bash

        # @raycast.schemaVersion 1
        # @raycast.title Hello
        # @raycast.mode \(mode)
        \(extra)
        echo hi
        """
    }

    @Test("a full Raycast header parses every key")
    func fullHeader() {
        let contents = """
        #!/bin/bash

        # Required parameters:
        # @raycast.schemaVersion 1
        # @raycast.title Say Hello
        # @raycast.mode fullOutput

        # Optional parameters:
        # @raycast.packageName Greetings
        # @raycast.icon 👋
        # @raycast.iconDark icons/dark.png
        # @raycast.currentDirectoryPath ../../work
        # @raycast.needsConfirmation true
        # @raycast.refreshTime 1h
        # @raycast.argument1 { "type": "text", "placeholder": "Name", "percentEncoded": true }
        # @raycast.argument2 { "type": "password", "placeholder": "Secret", "optional": true }
        # @raycast.argument3 { "type": "dropdown", "placeholder": "Tone", "data": [{"title": "Warm", "value": "warm"}, {"title": "Cold", "value": "cold"}] }
        # @raycast.description Greets someone.
        # @raycast.author Me

        echo "Hello $1"
        """
        let expected = ScriptCommand(
            path: path,
            title: "Say Hello",
            mode: .fullOutput,
            packageName: "Greetings",
            icon: .emoji("👋"),
            currentDirectoryPath: "/Users/me/work",
            needsConfirmation: true,
            refreshSeconds: 3_600,
            arguments: [
                ArgumentSpec(name: "Name", placeholder: "Name", percentEncoded: true),
                ArgumentSpec(name: "Secret", placeholder: "Secret", kind: .password, isOptional: true),
                ArgumentSpec(name: "Tone", placeholder: "Tone", kind: .dropdown([
                    ArgumentSpec.DropdownOption(title: "Warm", value: "warm"),
                    ArgumentSpec.DropdownOption(title: "Cold", value: "cold"),
                ])),
            ],
            description: "Greets someone."
        )
        #expect(command(contents) == expected)
    }

    @Test("a minimal header uses the defaults and the folder name as package")
    func minimal() {
        #expect(command(header()) == ScriptCommand(path: path, title: "Hello", mode: .silent, packageName: "tools"))
    }

    @Test("// comments work for Swift and JavaScript scripts, -- for AppleScript")
    func otherComments() {
        let swift = """
        #!/usr/bin/swift
        // @raycast.schemaVersion 1
        // @raycast.title Swifty
        //@raycast.mode compact
        print("hi")
        """
        #expect(command(swift)?.title == "Swifty")
        #expect(command(swift)?.mode == .compact)
        let appleScript = """
        #!/usr/bin/osascript
        -- @raycast.schemaVersion 1
        -- @raycast.title Apple
        -- @raycast.mode inline
        """
        #expect(command(appleScript)?.mode == .inline)
    }

    @Test("metadata outside comments is ignored and the first occurrence of a key wins")
    func onlyComments() {
        let contents = header("""
        echo "@raycast.title Not This"
        # @raycast.title Second
        ## @raycast.packageName Hashes
        """)
        #expect(command(contents)?.title == "Hello")
        #expect(command(contents)?.packageName == "Hashes")
    }

    @Test("missing required keys are reported in order schemaVersion, title, mode")
    func missingRequired() {
        #expect(error("# @raycast.title A\n# @raycast.mode silent") == .missingRequired("schemaVersion"))
        #expect(error("# @raycast.schemaVersion 1\n# @raycast.mode silent") == .missingRequired("title"))
        #expect(error("# @raycast.schemaVersion 1\n# @raycast.title A") == .missingRequired("mode"))
        #expect(error("# @raycast.schemaVersion 1\n# @raycast.title\n# @raycast.mode silent") == .missingRequired("title"))
        #expect(error("echo nothing") == .missingRequired("schemaVersion"))
    }

    @Test("only schema version 1 is supported and unknown values are rejected")
    func badValues() {
        #expect(error("# @raycast.schemaVersion 2\n# @raycast.title A\n# @raycast.mode silent") == .unsupportedSchema("2"))
        #expect(error(header(mode: "loud")) == .badValue(key: "mode", value: "loud"))
        #expect(error(header("# @raycast.needsConfirmation yes")) == .badValue(key: "needsConfirmation", value: "yes"))
        #expect(command(header(mode: "fulloutput"))?.mode == .fullOutput)
    }

    @Test("refresh times accept s, m, h and d with a ten second minimum")
    func refreshTime() {
        #expect(command(header("# @raycast.refreshTime 5s"))?.refreshSeconds == 10)
        #expect(command(header("# @raycast.refreshTime 10s"))?.refreshSeconds == 10)
        #expect(command(header("# @raycast.refreshTime 90s"))?.refreshSeconds == 90)
        #expect(command(header("# @raycast.refreshTime 1m"))?.refreshSeconds == 60)
        #expect(command(header("# @raycast.refreshTime 12h"))?.refreshSeconds == 43_200)
        #expect(command(header("# @raycast.refreshTime 1d"))?.refreshSeconds == 86_400)
        #expect(command(header())?.refreshSeconds == nil)
        for bad in ["10", "s", "0s", "1w", "-5m", "1.5h"] {
            #expect(error(header("# @raycast.refreshTime \(bad)")) == .badValue(key: "refreshTime", value: bad))
        }
    }

    @Test("argument JSON is validated and unnamed arguments get a positional name")
    func arguments() {
        #expect(command(header("# @raycast.argument1 {\"type\": \"text\"}"))?.arguments
            == [ArgumentSpec(name: "Argument 1", placeholder: "")])
        #expect(command(header("# @raycast.argument2 {\"placeholder\": \"Query\"}"))?.arguments
            == [ArgumentSpec(name: "Query", placeholder: "Query")])
        let bad = [
            "{not json}",
            "[1, 2]",
            "{\"type\": \"number\", \"placeholder\": \"N\"}",
            "{\"type\": \"dropdown\", \"placeholder\": \"Pick\"}",
            "{\"type\": \"dropdown\", \"placeholder\": \"Pick\", \"data\": [{\"title\": \"A\"}]}",
            "{\"placeholder\": \"N\", \"optional\": \"yes\"}",
            "{\"placeholder\": 3}",
        ]
        for json in bad {
            #expect(error(header("# @raycast.argument1 \(json)")) == .badValue(key: "argument1", value: json))
        }
        #expect(command(header("# @raycast.argument4 {\"placeholder\": \"X\"}"))?.arguments == [])
    }

    @Test("icons: emoji, https URL, or a path relative to the script's folder")
    func icons() {
        #expect(command(header("# @raycast.icon 🚀"))?.icon == .emoji("🚀"))
        #expect(command(header("# @raycast.icon https://example.com/icon.png"))?.icon
            == .url(URL(string: "https://example.com/icon.png")!))
        #expect(command(header("# @raycast.icon images/icon.png"))?.icon == .file(path: "/Users/me/scripts/tools/images/icon.png"))
        #expect(command(header("# @raycast.icon ../shared/icon.png"))?.icon == .file(path: "/Users/me/scripts/shared/icon.png"))
        #expect(command(header("# @raycast.icon /opt/icons/x.png"))?.icon == .file(path: "/opt/icons/x.png"))
        #expect(command(header("# @raycast.iconDark dark.png"))?.icon == nil)
    }

    @Test("the working directory resolves relative to the script's folder")
    func currentDirectory() {
        #expect(command(header("# @raycast.currentDirectoryPath ."))?.currentDirectoryPath == "/Users/me/scripts/tools")
        #expect(command(header("# @raycast.currentDirectoryPath /Users/me/work"))?.currentDirectoryPath == "/Users/me/work")
    }
}
