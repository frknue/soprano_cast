import Foundation

/// settings.json → `CastSettings`. Every key is optional; a bad value keeps its default
/// and becomes a `.warning` naming its dotted path ("launcher.screen", "quicklinks[2].id",
/// "hotkeys.app:com.google.Chrome"), the value found and what is allowed.
public enum SettingsResolver {
    /// Characters an alias may contain (after lowercasing).
    public static let aliasCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789 ")
    /// Characters a quicklink id may contain.
    public static let quicklinkIDCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-")

    /// JSONC (comments, trailing commas) → settings over the defaults. A document that is
    /// not a JSON object gives `settings == nil` and one `.error` issue with its line.
    /// Every bad value is a `.warning` and keeps its default; unknown keys warn.
    public static func resolve(text: String, knownThemeIDs: Set<String>) -> SettingsResolution {
        let root: [String: Any]
        do {
            let data = try JSONCText.strictJSONData(from: text)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dictionary = object as? [String: Any] else {
                let line = firstValueLine(in: String(decoding: data, as: UTF8.self))
                return failure("settings.json must be a JSON object", line: line)
            }
            root = dictionary
        } catch let error as JSONCText.ParseError {
            return failure(error.message, line: error.line)
        } catch {
            return failure("settings.json could not be read: \(error.localizedDescription)", line: 1)
        }

        var reader = Reader(knownThemeIDs: knownThemeIDs)
        let settings = reader.settings(from: root)
        return SettingsResolution(settings: settings, issues: reader.issues)
    }

    private static func failure(_ message: String, line: Int) -> SettingsResolution {
        SettingsResolution(settings: nil, issues: [ConfigIssue(severity: .error, message: message, line: line)])
    }

    /// The 1-based line of the first value in strict JSON text. Comment stripping keeps
    /// every newline, so lines match the original document.
    private static func firstValueLine(in text: String) -> Int {
        var line = 1
        for character in text {
            if character.isNewline {
                line += 1
            } else if !character.isWhitespace {
                break
            }
        }
        return line
    }
}

// MARK: - Reader

/// One resolution pass: reads sections over the defaults and collects issues.
private struct Reader {
    let knownThemeIDs: Set<String>
    var issues: [ConfigIssue] = []

    init(knownThemeIDs: Set<String>) {
        self.knownThemeIDs = knownThemeIDs
    }

    static let rootKeys: Set<String> = [
        "theme", "launcher", "hotkeys", "aliases", "favorites", "disabled", "fallbacks",
        "quicklinks", "scriptDirectories", "applicationDirectories", "hyperKey",
        "windowManagement", "app",
    ]
    static let quicklinkKeys: Set<String> = ["id", "name", "link", "openWith", "icon"]

    mutating func settings(from root: [String: Any]) -> CastSettings {
        var settings = CastSettings()
        warnUnknownKeys(in: root, path: nil, known: Self.rootKeys)

        if let value = root["theme"] {
            settings.theme = theme(value, current: settings.theme) ?? settings.theme
        }
        if let launcher = section("launcher", in: root, path: nil) {
            settings.launcher = self.launcher(launcher)
        }
        // Before hotkeys: whether Hyper includes Shift decides which hotkeys are the same.
        if let hyperKey = section("hyperKey", in: root, path: nil) {
            settings.hyperKey = self.hyperKey(hyperKey)
        }
        if let hotkeys = section("hotkeys", in: root, path: nil) {
            settings.hotkeys = self.hotkeys(hotkeys, launcherHotkey: settings.launcher.hotkey, hyperIncludesShift: settings.hyperKey.includeShift)
        }
        if let aliases = section("aliases", in: root, path: nil) {
            settings.aliases = self.aliases(aliases)
        }
        if let value = root["favorites"] {
            settings.favorites = itemList(value, path: "favorites", kept: "kept no favorites") ?? settings.favorites
        }
        if let value = root["disabled"] {
            settings.disabled = itemList(value, path: "disabled", kept: "kept nothing disabled").map { Set($0) } ?? settings.disabled
        }
        if let value = root["fallbacks"] {
            let kept = "kept " + settings.fallbacks.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            settings.fallbacks = itemList(value, path: "fallbacks", kept: kept) ?? settings.fallbacks
        }
        if let value = root["quicklinks"] {
            settings.quicklinks = quicklinks(value)
        }
        if let value = root["scriptDirectories"] {
            settings.scriptDirectories = directories(value, path: "scriptDirectories") ?? settings.scriptDirectories
        }
        if let value = root["applicationDirectories"] {
            settings.applicationDirectories = directories(value, path: "applicationDirectories") ?? settings.applicationDirectories
        }
        if let windowManagement = section("windowManagement", in: root, path: nil) {
            settings.windowManagement = self.windowManagement(windowManagement)
        }
        if let app = section("app", in: root, path: nil) {
            warnUnknownKeys(in: app, path: "app", known: ["startAtLogin", "showMenuBarIcon"])
            bool("startAtLogin", in: app, path: "app", into: &settings.app.startAtLogin)
            bool("showMenuBarIcon", in: app, path: "app", into: &settings.app.showMenuBarIcon)
        }
        return settings
    }

    // MARK: Sections

    private mutating func launcher(_ object: [String: Any]) -> LauncherSettings {
        let path = "launcher"
        warnUnknownKeys(in: object, path: path, known: ["hotkey", "screen", "popToRootSeconds", "navigation", "closeOnFocusLoss"])
        var launcher = LauncherSettings()
        if let value = object["hotkey"] {
            if value is NSNull {
                launcher.hotkey = nil
            } else if let text = value as? String, let spec = HotkeySpec(settingsText: text) {
                launcher.hotkey = spec
            } else {
                warn("\(path).hotkey: \(describe(value)) is not a hotkey like \"cmd+space\" or null; kept \(describeHotkey(launcher.hotkey)).")
            }
        }
        choice("screen", in: object, path: path, into: &launcher.screen)
        clampedInteger("popToRootSeconds", in: object, path: path, range: LauncherSettings.popToRootRange, unit: "seconds", into: &launcher.popToRootSeconds)
        choice("navigation", in: object, path: path, into: &launcher.navigation)
        bool("closeOnFocusLoss", in: object, path: path, into: &launcher.closeOnFocusLoss)
        return launcher
    }

    private mutating func hyperKey(_ object: [String: Any]) -> HyperKeySettings {
        let path = "hyperKey"
        warnUnknownKeys(in: object, path: path, known: ["trigger", "includeShift", "quickPress"])
        var hyperKey = HyperKeySettings()
        if let value = object["trigger"] {
            if value is NSNull {
                hyperKey.trigger = nil
            } else if let raw = value as? String, let trigger = HyperTrigger(rawValue: raw) {
                hyperKey.trigger = trigger
            } else {
                warn("\(path).trigger: \(describe(value)) is not one of \(allowed(HyperTrigger.self)) or null; kept null.")
            }
        }
        bool("includeShift", in: object, path: path, into: &hyperKey.includeShift)
        choice("quickPress", in: object, path: path, into: &hyperKey.quickPress)
        if hyperKey.quickPress != .nothing, hyperKey.trigger != .capsLock {
            warn("\(path).quickPress: \"\(hyperKey.quickPress.rawValue)\" needs trigger \"capsLock\"; kept \"nothing\".")
            hyperKey.quickPress = .nothing
        }
        return hyperKey
    }

    private mutating func windowManagement(_ object: [String: Any]) -> WindowManagementSettings {
        let path = "windowManagement"
        warnUnknownKeys(in: object, path: path, known: ["gap", "halves"])
        var windowManagement = WindowManagementSettings()
        clampedInteger("gap", in: object, path: path, range: WindowManagementSettings.gapRange, unit: "points", into: &windowManagement.gap)
        choice("halves", in: object, path: path, into: &windowManagement.halves)
        return windowManagement
    }

    // MARK: Hotkeys and aliases

    /// Item hotkeys in sorted id order. `null` means no hotkey; a spec already used by
    /// `launcher.hotkey` or by an earlier id (compared with Hyper expanded) is dropped.
    private mutating func hotkeys(_ object: [String: Any], launcherHotkey: HotkeySpec?, hyperIncludesShift: Bool) -> [ItemID: HotkeySpec] {
        let launcherSpec = launcherHotkey.map { expanded($0, hyperIncludesShift: hyperIncludesShift) }
        var result: [ItemID: HotkeySpec] = [:]
        var owners: [HotkeySpec: ItemID] = [:]
        for rawID in object.keys.sorted() {
            let path = "hotkeys.\(rawID)"
            guard let id = itemID(rawID, path: path), let value = object[rawID] else { continue }
            if value is NSNull { continue }
            guard let text = value as? String, let spec = HotkeySpec(settingsText: text) else {
                warn("\(path): \(describe(value)) is not a hotkey like \"cmd+1\", \"hyper+k\", \"rcmd\", \"double:cmd\" or \"both:shift\", or null; dropped.")
                continue
            }
            let key = expanded(spec, hyperIncludesShift: hyperIncludesShift)
            if key == launcherSpec {
                warn("\(path): \"\(text)\" is launcher.hotkey; dropped.")
                continue
            }
            if let owner = owners[key] {
                warn("\(path): \"\(text)\" is already the hotkey of \(owner.rawValue); dropped.")
                continue
            }
            owners[key] = id
            result[id] = spec
        }
        return result
    }

    /// `spec` with `hyper` replaced by the modifiers it stands for, for comparisons.
    private func expanded(_ spec: HotkeySpec, hyperIncludesShift: Bool) -> HotkeySpec {
        guard case .combo(let combo) = spec, combo.usesHyper else { return spec }
        return .combo(HotkeyCombo(modifiers: combo.effectiveModifiers(hyperIncludesShift: hyperIncludesShift), key: combo.key))
    }

    /// Lowercased aliases; `null` means none. Two items sharing an alias both keep it.
    private mutating func aliases(_ object: [String: Any]) -> [ItemID: String] {
        var result: [ItemID: String] = [:]
        var owners: [String: ItemID] = [:]
        for rawID in object.keys.sorted() {
            let path = "aliases.\(rawID)"
            guard let id = itemID(rawID, path: path), let value = object[rawID] else { continue }
            if value is NSNull { continue }
            guard let text = value as? String else {
                warn("\(path): \(describe(value)) is not an alias string or null; dropped.")
                continue
            }
            let alias = text.lowercased().trimmingCharacters(in: .whitespaces)
            guard !alias.isEmpty else {
                warn("\(path): \(describe(value)) is empty; dropped.")
                continue
            }
            guard alias.allSatisfy({ SettingsResolver.aliasCharacters.contains($0) }) else {
                warn("\(path): \(describe(value)) may only contain a–z, 0–9 and spaces; dropped.")
                continue
            }
            if let owner = owners[alias] {
                warn("\(path): \"\(alias)\" is also the alias of \(owner.rawValue).")
            } else {
                owners[alias] = id
            }
            result[id] = alias
        }
        return result
    }

    // MARK: Lists

    /// An array of item ids in order, bad and repeated entries dropped; nil (with a
    /// warning ending in `kept`) when `value` is not an array.
    private mutating func itemList(_ value: Any, path: String, kept: String) -> [ItemID]? {
        guard let entries = value as? [Any] else {
            warn("\(path): \(describe(value)) is not an array of item ids; \(kept).")
            return nil
        }
        var result: [ItemID] = []
        for (index, entry) in entries.enumerated() {
            let entryPath = "\(path)[\(index)]"
            guard let raw = entry as? String else {
                warn("\(entryPath): \(describe(entry)) is not an item id; dropped.")
                continue
            }
            guard let id = itemID(raw, path: entryPath) else { continue }
            if result.contains(id) {
                warn("\(entryPath): \"\(raw)\" is listed twice; dropped.")
                continue
            }
            result.append(id)
        }
        return result
    }

    /// An array of non-empty folder paths; nil (with a warning) when not an array.
    private mutating func directories(_ value: Any, path: String) -> [String]? {
        guard let entries = value as? [Any] else {
            warn("\(path): \(describe(value)) is not an array of folder paths; kept none.")
            return nil
        }
        var result: [String] = []
        for (index, entry) in entries.enumerated() {
            guard let text = entry as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                warn("\(path)[\(index)]: \(describe(entry)) is not a folder path; dropped.")
                continue
            }
            result.append(text)
        }
        return result
    }

    private mutating func quicklinks(_ value: Any) -> [Quicklink] {
        guard let entries = value as? [Any] else {
            warn("quicklinks: \(describe(value)) is not an array of quicklinks; kept none.")
            return []
        }
        var result: [Quicklink] = []
        var indices: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            let path = "quicklinks[\(index)]"
            guard let object = entry as? [String: Any] else {
                warn("\(path): \(describe(entry)) is not an object; dropped.")
                continue
            }
            warnUnknownKeys(in: object, path: path, known: Self.quicklinkKeys)

            guard let id = object["id"] as? String, !id.isEmpty, id.allSatisfy({ SettingsResolver.quicklinkIDCharacters.contains($0) }) else {
                let found = object["id"].map { describe($0) } ?? "missing"
                warn("\(path).id: \(found) is not an id of a–z, 0–9 and \"-\"; quicklink dropped.")
                continue
            }
            if let earlier = indices[id] {
                warn("\(path).id: \"\(id)\" is already the id of quicklinks[\(earlier)]; quicklink dropped.")
                continue
            }
            guard let name = requiredText("name", in: object, path: path) else { continue }
            guard let link = requiredText("link", in: object, path: path) else { continue }

            var quicklink = Quicklink(id: id, name: name, link: link)
            quicklink.openWith = optionalText("openWith", in: object, path: path, meaning: "a bundle id, app name or app path")
            quicklink.icon = optionalText("icon", in: object, path: path, meaning: "an emoji or image path")
            indices[id] = index
            result.append(quicklink)
        }
        return result
    }

    /// A required non-empty string; nil with a "quicklink dropped" warning otherwise.
    private mutating func requiredText(_ key: String, in object: [String: Any], path: String) -> String? {
        if let text = object[key] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            return text
        }
        let found = object[key].map { describe($0) } ?? "missing"
        warn("\(path).\(key): \(found) is not a non-empty string; quicklink dropped.")
        return nil
    }

    /// An optional string: absent, null or "" → nil; anything else that is not a string warns.
    private mutating func optionalText(_ key: String, in object: [String: Any], path: String, meaning: String) -> String? {
        guard let value = object[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else {
            warn("\(path).\(key): \(describe(value)) is not \(meaning) or null; ignored.")
            return nil
        }
        return text.isEmpty ? nil : text
    }

    // MARK: Helpers

    private mutating func warn(_ message: String) {
        issues.append(ConfigIssue(severity: .warning, message: message))
    }

    private func join(_ path: String?, _ key: String) -> String {
        path.map { "\($0).\(key)" } ?? key
    }

    private mutating func warnUnknownKeys(in object: [String: Any], path: String?, known: Set<String>) {
        for key in object.keys.sorted() where !known.contains(key) {
            warn("Unknown setting \"\(join(path, key))\".")
        }
    }

    /// The object at `key`, or nil (with a warning when present but not an object).
    private mutating func section(_ key: String, in object: [String: Any], path: String?) -> [String: Any]? {
        guard let value = object[key] else { return nil }
        guard let section = value as? [String: Any] else {
            warn("\(join(path, key)): \(describe(value)) is not an object; ignored.")
            return nil
        }
        return section
    }

    /// An item id with a known kind prefix and a non-empty key; nil with a warning
    /// otherwise. Ids of items that don't exist right now are fine (apps get installed later).
    private mutating func itemID(_ raw: String, path: String) -> ItemID? {
        let id = ItemID(rawValue: raw)
        if id.kind != nil, !id.key.isEmpty { return id }
        let kinds = ItemKind.allCases.map { "\"\($0.prefix):\"" }.joined(separator: ", ")
        warn("\(path): \"\(raw)\" is not an item id starting with one of \(kinds); dropped.")
        return nil
    }

    private mutating func bool(_ key: String, in object: [String: Any], path: String, into target: inout Bool) {
        guard let value = object[key] else { return }
        if let flag = boolean(value) {
            target = flag
        } else {
            warn("\(path).\(key): \(describe(value)) is not true or false; kept \(target).")
        }
    }

    /// A whole number clamped into `range` (with a warning when it had to be clamped).
    private mutating func clampedInteger(
        _ key: String,
        in object: [String: Any],
        path: String,
        range: ClosedRange<Int>,
        unit: String,
        into target: inout Int
    ) {
        guard let value = object[key] else { return }
        guard let number = integer(value) else {
            warn("\(path).\(key): \(describe(value)) is not a whole number of \(unit); kept \(target).")
            return
        }
        let clamped = min(max(range.lowerBound, number), range.upperBound)
        if clamped != number {
            warn("\(path).\(key): \(number) is outside \(range.lowerBound)–\(range.upperBound); clamped to \(clamped).")
        }
        target = clamped
    }

    /// An enum value by its rawValue; a bad value warns with the allowed values.
    private mutating func choice<Value: RawRepresentable & CaseIterable>(
        _ key: String,
        in object: [String: Any],
        path: String,
        into target: inout Value
    ) where Value.RawValue == String {
        guard let value = object[key] else { return }
        if let raw = value as? String, let parsed = Value(rawValue: raw) {
            target = parsed
        } else {
            warn("\(path).\(key): \(describe(value)) is not one of \(allowed(Value.self)); kept \"\(target.rawValue)\".")
        }
    }

    /// A known theme id, or nil with a warning naming the known ids.
    private mutating func theme(_ value: Any, current: String) -> String? {
        if let id = value as? String, id == "soprano" || knownThemeIDs.contains(id) {
            return id
        }
        let known = (["soprano"] + knownThemeIDs.subtracting(["soprano"]).sorted()).map { "\"\($0)\"" }.joined(separator: ", ")
        warn("theme: \(describe(value)) is not a known theme; kept \"\(current)\". Known themes: \(known).")
        return nil
    }

    private func allowed<Value: RawRepresentable & CaseIterable>(_: Value.Type) -> String where Value.RawValue == String {
        Value.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
    }

    /// JSON booleans only (JSONSerialization gives NSNumber for both numbers and booleans).
    private func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// JSON numbers without a fractional part.
    private func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) < 1e9 else { return nil }
        return Int(double)
    }

    private func describe(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case is [Any]:
            return "an array"
        case is [String: Any]:
            return "an object"
        default:
            return String(describing: value)
        }
    }

    private func describeHotkey(_ spec: HotkeySpec?) -> String {
        spec.map { "\"\($0.settingsText)\"" } ?? "null"
    }
}
