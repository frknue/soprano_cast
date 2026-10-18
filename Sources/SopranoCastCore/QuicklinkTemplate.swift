import Foundation

/// Values for the non-argument quicklink placeholders.
public struct PlaceholderContext: Sendable {
    public var clipboard: String
    public var now: Date
    public var uuid: String

    public init(clipboard: String, now: Date, uuid: String) {
        self.clipboard = clipboard
        self.now = now
        self.uuid = uuid
    }
}

/// Raycast's quicklink placeholders: `{argument name="x" default="y"}` (attributes in any
/// order), `{argument}` and legacy `{Query}`/`{query}` (both the argument "Query"),
/// `{clipboard}`, `{date}`, `{time}`, `{uuid}`. Anything else in braces stays literal.
public enum QuicklinkTemplate {
    /// Arguments from `{argument name="x" default="y"}`, `{argument}` ("Query") and legacy
    /// `{Query}`/`{query}`, in order, deduplicated by name, at most 3; a `default` makes it optional.
    public static func arguments(in link: String) -> [ArgumentSpec] {
        var specs: [ArgumentSpec] = []
        for case .argument(let name, let defaultValue) in segments(of: link).compactMap(\.placeholder) {
            guard !specs.contains(where: { $0.name == name }) else { continue }
            guard specs.count < maxArguments else { break }
            specs.append(ArgumentSpec(name: name, placeholder: name, isOptional: defaultValue != nil))
        }
        return specs
    }

    /// Substitutes arguments (empty → default), {clipboard}, {date} (yyyy-MM-dd), {time}
    /// (HH:mm), {uuid}. Values are percent-encoded (URL query-safe) when the link has a
    /// URL scheme, raw for file paths. A leading "~" expands to `home`.
    ///
    /// `arguments` are positional, in `arguments(in:)` order; a missing one counts as empty.
    /// Each placeholder falls back to its own `default`, then to the first occurrence's.
    /// Argument placeholders beyond the first three names expand to their default or "".
    public static func expand(_ link: String, arguments: [String], context: PlaceholderContext, home: String) -> String {
        let specs = self.arguments(in: link)
        let sharedDefaults = firstDefaults(in: link)
        let encodes = hasURLScheme(link)
        let template = expandingTilde(link, home: home)

        var result = ""
        for segment in segments(of: template) {
            switch segment {
            case .literal(let text):
                result += text
            case .placeholder(let placeholder):
                let value: String
                switch placeholder {
                case .argument(let name, let defaultValue):
                    let index = specs.firstIndex { $0.name == name }
                    let given = index.flatMap { $0 < arguments.count ? arguments[$0] : nil } ?? ""
                    value = given.isEmpty ? (defaultValue ?? sharedDefaults[name] ?? "") : given
                case .clipboard: value = context.clipboard
                case .date: value = dateString(context.now)
                case .time: value = timeString(context.now)
                case .uuid: value = context.uuid
                }
                result += encodes ? percentEncoded(value) : value
            }
        }
        return result
    }

    static let maxArguments = 3

    /// Characters `encodeURIComponent` leaves alone: safe inside a query value or a path segment.
    static let componentSafe = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: componentSafe) ?? value
    }

    /// `^[a-zA-Z][a-zA-Z0-9+.-]*:` — https:, mailto:, raycast:, slack:, …
    static func hasURLScheme(_ link: String) -> Bool {
        guard let first = link.unicodeScalars.first, isASCIILetter(first) else { return false }
        for scalar in link.unicodeScalars.dropFirst() {
            if scalar == ":" { return true }
            guard isASCIILetter(scalar) || ("0"..."9").contains(scalar) || "+.-".unicodeScalars.contains(scalar) else {
                return false
            }
        }
        return false
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private static func expandingTilde(_ link: String, home: String) -> String {
        guard link == "~" || link.hasPrefix("~/") else { return link }
        return home + link.dropFirst()
    }

    private static func dateString(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func timeString(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02ld:%02ld", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Gregorian in the current time zone, so {date}/{time} are the user's wall clock.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func firstDefaults(in link: String) -> [String: String] {
        var defaults: [String: String] = [:]
        for case .argument(let name, let defaultValue?) in segments(of: link).compactMap(\.placeholder)
        where defaults[name] == nil {
            defaults[name] = defaultValue
        }
        return defaults
    }

    // MARK: Parsing

    enum Placeholder: Equatable {
        case argument(name: String, defaultValue: String?)
        case clipboard
        case date
        case time
        case uuid
    }

    enum Segment: Equatable {
        case literal(String)
        case placeholder(Placeholder)

        var placeholder: Placeholder? {
            if case .placeholder(let placeholder) = self { placeholder } else { nil }
        }
    }

    /// The link split into literal text and recognized `{…}` placeholders.
    static func segments(of link: String) -> [Segment] {
        var segments: [Segment] = []
        var literal = ""
        var index = link.startIndex
        while index < link.endIndex {
            if link[index] == "{",
               let close = link[index...].firstIndex(of: "}"),
               let found = placeholder(String(link[link.index(after: index)..<close])) {
                if !literal.isEmpty { segments.append(.literal(literal)) }
                literal = ""
                segments.append(.placeholder(found))
                index = link.index(after: close)
            } else {
                literal.append(link[index])
                index = link.index(after: index)
            }
        }
        if !literal.isEmpty { segments.append(.literal(literal)) }
        return segments
    }

    private static func placeholder(_ body: String) -> Placeholder? {
        let text = body.trimmingCharacters(in: .whitespaces)
        switch text {
        case "Query", "query", "argument": return .argument(name: "Query", defaultValue: nil)
        case "clipboard": return .clipboard
        case "date": return .date
        case "time": return .time
        case "uuid": return .uuid
        default: break
        }
        guard text.hasPrefix("argument"),
              let first = text.dropFirst("argument".count).first, first.isWhitespace,
              let attributes = attributes(String(text.dropFirst("argument".count))) else { return nil }
        let name = attributes["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "Query"
        return .argument(name: name, defaultValue: attributes["default"])
    }

    /// `key="value"` pairs (double or single quotes) separated by whitespace; nil when malformed.
    private static func attributes(_ text: String) -> [String: String]? {
        var result: [String: String] = [:]
        var rest = Substring(text)
        while true {
            rest = rest.drop(while: \.isWhitespace)
            guard !rest.isEmpty else { return result }
            let key = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            guard !key.isEmpty else { return nil }
            rest = rest.dropFirst(key.count).drop(while: \.isWhitespace)
            guard rest.first == "=" else { return nil }
            rest = rest.dropFirst().drop(while: \.isWhitespace)
            guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
            rest = rest.dropFirst()
            guard let end = rest.firstIndex(of: quote) else { return nil }
            if result[String(key)] == nil { result[String(key)] = String(rest[..<end]) }
            rest = rest[rest.index(after: end)...]
        }
    }
}
