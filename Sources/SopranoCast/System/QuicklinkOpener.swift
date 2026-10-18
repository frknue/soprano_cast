import AppKit
import OSLog
import SopranoCastCore

private let quicklinkLog = Logger(subsystem: "com.soprano.cast", category: "quicklinks")

/// Opens quicklinks and other links (search engine URLs) in their app.
@MainActor
enum QuicklinkOpener {
    /// Folders an `openWith` app name is looked up in, in order.
    private static let applicationFolders = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "~/Applications",
        "/System/Library/CoreServices/Applications",
        "/System/Library/CoreServices",
    ]

    /// Expands the template and opens it (with `openWith` when set: bundle id, app name or path).
    static func open(_ quicklink: Quicklink, arguments: [String]) -> RunOutcome {
        let context = PlaceholderContext(
            clipboard: NSPasteboard.general.string(forType: .string) ?? "",
            now: Date(),
            uuid: UUID().uuidString
        )
        let link = QuicklinkTemplate.expand(quicklink.link, arguments: arguments, context: context, home: NSHomeDirectory())
        return open(urlString: link, openWith: quicklink.openWith)
    }

    static func open(urlString: String, openWith: String?) -> RunOutcome {
        let text = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = url(from: text) else {
            return .toast("Invalid link: \(text)", isError: true)
        }
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            return .toast("No such file: \((url.path as NSString).abbreviatingWithTildeInPath)", isError: true)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = openWith?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !application.isEmpty else {
            NSWorkspace.shared.open(url, configuration: configuration) { _, error in
                if let error {
                    quicklinkLog.error("Opening \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return .done(closeLauncher: true)
        }
        guard let applicationURL = applicationURL(for: application) else {
            return .toast("Can't find \(application)", isError: true)
        }
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                quicklinkLog.error("Opening \(url.absoluteString, privacy: .public) with \(applicationURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return .done(closeLauncher: true)
    }

    // MARK: - Helpers

    /// A link with a URL scheme ("https:", "raycast:", "mailto:") as a URL — percent-encoding
    /// characters URLs don't allow, like spaces typed into the link — else a file path
    /// (~ expanded). nil when neither works.
    static func url(from text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        guard hasScheme(text) else {
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        if let url = URL(string: text) { return url }
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.insert(charactersIn: "#%")
        return text.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: $0) }
    }

    /// Whether `text` starts with `scheme:` (a letter, then letters, digits, "+", "-", ".").
    private static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first) else {
            return false
        }
        return scheme.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "+-.".unicodeScalars.contains(scalar))
        }
    }

    /// `openWith` as an app: a path ("/Applications/Arc.app", "~/Applications/X.app"), a
    /// bundle id ("com.google.Chrome") or an app name ("Google Chrome", "Safari.app").
    private static func applicationURL(for openWith: String) -> URL? {
        let fileManager = FileManager.default
        if openWith.hasPrefix("/") || openWith.hasPrefix("~") {
            let path = (openWith as NSString).expandingTildeInPath
            return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: openWith) {
            return url
        }
        let name = openWith.lowercased().hasSuffix(".app") ? String(openWith.dropLast(4)) : openWith
        for folder in applicationFolders {
            let path = ((folder as NSString).expandingTildeInPath as NSString).appendingPathComponent("\(name).app")
            if fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
