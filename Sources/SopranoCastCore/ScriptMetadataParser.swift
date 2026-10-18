import Foundation

public enum ScriptParseError: Error, Equatable, Sendable {
    case missingRequired(String)       // "schemaVersion", "title", "mode"
    case unsupportedSchema(String)
    case badValue(key: String, value: String)
}

/// Raycast's script-command metadata (github.com/raycast/script-commands README).
public enum ScriptMetadataParser {
    /// `@raycast.<key> <value>` lines in `#` or `//` comments: schemaVersion (1), title, mode,
    /// packageName (default: `directoryName`), icon (emoji → .emoji; https URL → .url; else a
    /// path relative to the script's folder → .file), iconDark (ignored), currentDirectoryPath,
    /// needsConfirmation, refreshTime ("10s" "1m" "12h" "1d", minimum 10 s), argument1…3
    /// (JSON: type text|password|dropdown, placeholder, optional, percentEncoded, data
    /// [{title,value}]), description. Files whose name contains ".template." are rejected by
    /// the caller.
    ///
    /// AppleScript's `--` comments are read too. The first occurrence of a key wins; keys
    /// without a value count as absent. `currentDirectoryPath` is resolved like the icon
    /// (~ expanded, relative to the script's folder). Required keys are checked in the
    /// order schemaVersion, title, mode.
    public static func parse(contents: String, path: String, directoryName: String) -> Result<ScriptCommand, ScriptParseError> {
        let values = metadata(in: contents)
        let folder = (path as NSString).deletingLastPathComponent

        guard let schema = values["schemaVersion"] else { return .failure(.missingRequired("schemaVersion")) }
        guard schema == "1" else { return .failure(.unsupportedSchema(schema)) }
        guard let title = values["title"] else { return .failure(.missingRequired("title")) }
        guard let modeText = values["mode"] else { return .failure(.missingRequired("mode")) }
        guard let mode = ScriptCommand.Mode.allCases.first(where: { $0.rawValue.lowercased() == modeText.lowercased() }) else {
            return .failure(.badValue(key: "mode", value: modeText))
        }

        var needsConfirmation = false
        if let text = values["needsConfirmation"] {
            switch text.lowercased() {
            case "true": needsConfirmation = true
            case "false": needsConfirmation = false
            default: return .failure(.badValue(key: "needsConfirmation", value: text))
            }
        }

        var refreshSeconds: Int?
        if let text = values["refreshTime"] {
            guard let interval = seconds(fromRefreshTime: text) else {
                return .failure(.badValue(key: "refreshTime", value: text))
            }
            refreshSeconds = max(minimumRefreshSeconds, interval)
        }

        var arguments: [ArgumentSpec] = []
        for index in 1...3 {
            let key = "argument\(index)"
            guard let json = values[key] else { continue }
            guard let spec = argument(fromJSON: json, index: index) else {
                return .failure(.badValue(key: key, value: json))
            }
            arguments.append(spec)
        }

        return .success(ScriptCommand(
            path: path,
            title: title,
            mode: mode,
            packageName: values["packageName"] ?? directoryName,
            icon: values["icon"].map { icon(from: $0, folder: folder) },
            currentDirectoryPath: values["currentDirectoryPath"].map { resolve($0, folder: folder) },
            needsConfirmation: needsConfirmation,
            refreshSeconds: refreshSeconds,
            arguments: arguments,
            description: values["description"]
        ))
    }

    static let minimumRefreshSeconds = 10

    /// Every `@raycast.<key> <value>` comment line, first occurrence per key.
    static func metadata(in contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.drop(while: \.isWhitespace)
            if line.hasPrefix("//") {
                line = line.dropFirst(2)
            } else if line.hasPrefix("--") {
                line = line.dropFirst(2)
            } else if line.hasPrefix("#") {
                line = line.drop { $0 == "#" }
            } else {
                continue
            }
            line = line.drop(while: \.isWhitespace)
            guard line.hasPrefix("@raycast.") else { continue }
            line = line.dropFirst("@raycast.".count)
            let key = String(line.prefix { !$0.isWhitespace })
            let value = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty, values[key] == nil else { continue }
            values[key] = value
        }
        return values
    }

    /// "10s", "1m", "12h", "1d" → seconds; nil when malformed or zero.
    static func seconds(fromRefreshTime text: String) -> Int? {
        guard let unit = text.last, let count = Int(text.dropLast()), count > 0 else { return nil }
        let multiplier: Int
        switch unit {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3_600
        case "d": multiplier = 86_400
        default: return nil
        }
        let (seconds, overflow) = count.multipliedReportingOverflow(by: multiplier)
        return overflow ? nil : seconds
    }

    /// An emoji → `.emoji`; an `https` URL → `.url`; else a path (~ allowed, relative to the
    /// script's folder) → `.file`.
    static func icon(from text: String, folder: String) -> ItemIcon {
        if IconText.isEmoji(text) { return .emoji(text) }
        if text.lowercased().hasPrefix("https://"), let url = URL(string: text) { return .url(url) }
        return .file(path: resolve(text, folder: folder))
    }

    private static func resolve(_ path: String, folder: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.hasPrefix("/") else { return (expanded as NSString).standardizingPath }
        return ((folder as NSString).appendingPathComponent(expanded) as NSString).standardizingPath
    }

    /// `{"type": "text", "placeholder": "Query", "optional": true, "percentEncoded": true}`;
    /// dropdowns need `"data": [{"title": …, "value": …}]`. The placeholder names the
    /// argument ("Argument N" without one).
    static func argument(fromJSON json: String, index: Int) -> ArgumentSpec? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let placeholder: String
        switch object["placeholder"] {
        case nil: placeholder = ""
        case let text as String: placeholder = text
        default: return nil
        }
        guard let isOptional = bool(object["optional"]), let percentEncoded = bool(object["percentEncoded"]) else {
            return nil
        }

        let kind: ArgumentSpec.Kind
        switch object["type"] as? String ?? (object["type"] == nil ? "text" : "") {
        case "text": kind = .text
        case "password": kind = .password
        case "dropdown":
            guard let entries = object["data"] as? [[String: Any]], !entries.isEmpty else { return nil }
            var options: [ArgumentSpec.DropdownOption] = []
            for entry in entries {
                guard let title = entry["title"] as? String, let value = entry["value"] as? String else { return nil }
                options.append(ArgumentSpec.DropdownOption(title: title, value: value))
            }
            kind = .dropdown(options)
        default: return nil
        }

        return ArgumentSpec(
            name: placeholder.isEmpty ? "Argument \(index)" : placeholder,
            placeholder: placeholder,
            kind: kind,
            isOptional: isOptional,
            percentEncoded: percentEncoded
        )
    }

    /// Absent → false; a JSON boolean → its value; anything else → nil.
    private static func bool(_ value: Any?) -> Bool? {
        guard let value else { return false }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
