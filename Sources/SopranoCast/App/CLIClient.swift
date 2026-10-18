import Foundation
import SopranoCastCore

/// `SopranoCast <command>`: sends one `CLIRequest` to the running app over its
/// `CFMessagePort` and prints the result.
enum CLIClient {
    /// First arguments that select the CLI instead of the GUI.
    static let commands: Set<String> = ["toggle", "open", "list", "help", "--help"]

    static let usage = """
    Usage: SopranoCast <command>

      toggle                          Open or close the launcher
      open <item-id> [argument…]      Run an item as its hotkey would, e.g. open app:com.google.Chrome
                                      or open cast:searchGoogle "swift testing"
      list                            List every item as JSON, sorted by title
      help                            Show this help

    """

    /// The request for command-line arguments (without the executable); nil for `help`
    /// and anything malformed.
    static func request(from arguments: [String]) -> CLIRequest? {
        guard let command = arguments.first else { return nil }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "toggle" where rest.isEmpty:
            return .toggleLauncher
        case "open":
            guard let id = rest.first, !id.isEmpty else { return nil }
            return .open(itemID: id, arguments: Array(rest.dropFirst()))
        case "list" where rest.isEmpty:
            return .list
        default:
            return nil
        }
    }

    /// Runs the command and exits: 0 (`list` prints its items as JSON, `help` the usage);
    /// 1 with the error on stderr; 2 with the usage on stderr for malformed arguments.
    static func run(arguments: [String]) -> Never {
        if let command = arguments.first, command == "help" || command == "--help" {
            print(usage, terminator: "")
            exit(0)
        }
        guard let request = request(from: arguments) else {
            fail(usage, status: 2)
        }
        let response: CLIResponse
        do {
            response = try send(request)
        } catch {
            fail("\(error.message)\n", status: 1)
        }
        guard response.ok else {
            fail("\(response.error ?? "The request failed.")\n", status: 1)
        }
        if let items = response.items {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(items), let text = String(data: data, encoding: .utf8) else {
                fail("Could not encode the response.\n", status: 1)
            }
            print(text)
        }
        exit(0)
    }

    struct Failure: Error {
        let message: String
    }

    private static func send(_ request: CLIRequest) throws(Failure) -> CLIResponse {
        guard let port = CFMessagePortCreateRemote(nil, CLIServer.portName as CFString) else {
            throw Failure(message: "Soprano Cast is not running.")
        }
        defer { CFMessagePortInvalidate(port) }
        guard let body = try? JSONEncoder().encode(request) else {
            throw Failure(message: "Could not encode the request.")
        }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port,
            0,
            body as CFData,
            2,
            2,
            CFRunLoopMode.defaultMode.rawValue,
            &reply
        )
        let replyData = reply?.takeRetainedValue()
        guard status == kCFMessagePortSuccess, let replyData else {
            throw Failure(message: status == kCFMessagePortReceiveTimeout || status == kCFMessagePortSendTimeout
                ? "Soprano Cast did not answer."
                : "Soprano Cast is not running.")
        }
        guard let response = try? JSONDecoder().decode(CLIResponse.self, from: replyData as Data) else {
            throw Failure(message: "Soprano Cast sent an unreadable response.")
        }
        return response
    }

    private static func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data(message.utf8))
        exit(status)
    }
}
