import AppKit
import Testing
@testable import SopranoCastCore

struct QuicklinkTemplateTests {
    private let context: PlaceholderContext = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 7, minute: 9))!
        return PlaceholderContext(clipboard: "a b&c", now: now, uuid: "1F2E3D4C-0000-4000-8000-000000000001")
    }()

    private func expand(_ link: String, _ arguments: [String] = []) -> String {
        QuicklinkTemplate.expand(link, arguments: arguments, context: context, home: "/Users/me")
    }

    @Test("named arguments keep their order, attributes may come in any order, and a default makes one optional")
    func namedArguments() {
        let link = "https://x.example/{argument name=\"repo\"}/{argument default=\"main\" name=\"branch\"}"
        #expect(QuicklinkTemplate.arguments(in: link) == [
            ArgumentSpec(name: "repo", placeholder: "repo"),
            ArgumentSpec(name: "branch", placeholder: "branch", isOptional: true),
        ])
    }

    @Test("bare {argument} and legacy {Query}/{query} are one argument named Query")
    func queryArguments() {
        #expect(QuicklinkTemplate.arguments(in: "https://g.example/?q={argument}") == [ArgumentSpec(name: "Query", placeholder: "Query")])
        #expect(QuicklinkTemplate.arguments(in: "https://g.example/?q={Query}&again={query}&more={argument}")
            == [ArgumentSpec(name: "Query", placeholder: "Query")])
    }

    @Test("arguments are deduplicated by name and capped at three")
    func dedupeAndCap() {
        let link = "x:{argument name=\"a\"}{argument name=\"b\"}{argument name=\"a\"}{argument name=\"c\"}{argument name=\"d\"}"
        #expect(QuicklinkTemplate.arguments(in: link).map { $0.name } == ["a", "b", "c"])
    }

    @Test("context placeholders, unknown braces and malformed attributes are not arguments")
    func notArguments() {
        #expect(QuicklinkTemplate.arguments(in: "https://x.example/{clipboard}/{date}/{time}/{uuid}/{foo}").isEmpty)
        #expect(QuicklinkTemplate.arguments(in: "https://x.example/{argument name=repo}").isEmpty)
        #expect(QuicklinkTemplate.arguments(in: "https://x.example/{arguments}").isEmpty)
        #expect(expand("https://x.example/{foo}/{argument name=repo}") == "https://x.example/{foo}/{argument name=repo}")
    }

    @Test("values in links with a URL scheme are percent-encoded like a query component")
    func urlEncoding() {
        #expect(expand("https://www.google.com/search?q={argument}", ["swift concurrency & actors"])
            == "https://www.google.com/search?q=swift%20concurrency%20%26%20actors")
        #expect(expand("https://x.example/{argument name=\"p\"}", ["a/b?c=d#e+f"]) == "https://x.example/a%2Fb%3Fc%3Dd%23e%2Bf")
        #expect(expand("mailto:{argument}", ["ü@x.de"]) == "mailto:%C3%BC%40x.de")
        #expect(expand("x-apple.systempreferences:{argument}", ["a b"]) == "x-apple.systempreferences:a%20b")
        #expect(expand("https://x.example/?c={clipboard}") == "https://x.example/?c=a%20b%26c")
    }

    @Test("values in file paths are substituted raw and a leading ~ expands to home")
    func pathsRaw() {
        #expect(expand("~/Projects/{argument name=\"project\"}", ["my app & co"]) == "/Users/me/Projects/my app & co")
        #expect(expand("/Volumes/{clipboard}") == "/Volumes/a b&c")
        #expect(expand("~") == "/Users/me")
        #expect(expand("/tmp/~x") == "/tmp/~x")
        #expect(expand("~other/x") == "~other/x")
    }

    @Test("empty or missing values fall back to the placeholder's default")
    func defaults() {
        let link = "https://x.example/{argument name=\"repo\" default=\"swift\"}/{argument name=\"tab\"}"
        #expect(expand(link, ["", "issues"]) == "https://x.example/swift/issues")
        #expect(expand(link, []) == "https://x.example/swift/")
        #expect(expand(link, ["apple", "pulls"]) == "https://x.example/apple/pulls")
        #expect(expand("x:{argument name=\"a\" default=\"1\"}-{argument name=\"a\"}", [""]) == "x:1-1")
    }

    @Test("repeated placeholders share one value and names past three expand to their default")
    func repeatedAndOverflow() {
        #expect(expand("https://x.example/{Query}/{argument}", ["hi"]) == "https://x.example/hi/hi")
        let link = "/{argument name=\"a\"}/{argument name=\"b\"}/{argument name=\"c\"}/{argument name=\"d\" default=\"z\"}"
        #expect(expand(link, ["1", "2", "3", "4"]) == "/1/2/3/z")
    }

    @Test("date, time, uuid and clipboard come from the context")
    func contextPlaceholders() {
        #expect(expand("/notes/{date} {time} {uuid}.md") == "/notes/2026-03-05 07:09 1F2E3D4C-0000-4000-8000-000000000001.md")
        #expect(expand("https://x.example/{date}") == "https://x.example/2026-03-05")
        #expect(expand("https://x.example/{time}") == "https://x.example/07%3A09")
    }
}
