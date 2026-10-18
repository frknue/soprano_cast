import Foundation
import OSLog
import SopranoCastCore

private let stateLog = Logger(subsystem: "com.soprano.cast", category: "state")

/// What Soprano Cast remembers between launches besides settings.json: item usage (for
/// frecency) and the search history, as JSON data in `UserDefaults`.
@MainActor
final class AppStateStore {
    /// `[String: UsageRecord]` keyed by item id raw value.
    static let usageKey = "castUsage"
    /// `[String]`, newest first.
    static let historyKey = "castHistory"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stored usage; empty when nothing (or unreadable data) is stored.
    func loadUsage() -> [ItemID: UsageRecord] {
        guard let data = defaults.data(forKey: Self.usageKey) else { return [:] }
        do {
            let stored = try JSONDecoder().decode([String: UsageRecord].self, from: data)
            return Dictionary(uniqueKeysWithValues: stored.map { (ItemID(rawValue: $0.key), $0.value) })
        } catch {
            stateLog.error("Could not read stored usage: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    func saveUsage(_ usage: [ItemID: UsageRecord]) {
        let stored = Dictionary(uniqueKeysWithValues: usage.map { ($0.key.rawValue, $0.value) })
        save(stored, forKey: Self.usageKey)
    }

    /// Stored search history; empty when nothing (or unreadable data) is stored.
    func loadHistory() -> [String] {
        guard let data = defaults.data(forKey: Self.historyKey) else { return [] }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            stateLog.error("Could not read stored search history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func saveHistory(_ entries: [String]) {
        save(entries, forKey: Self.historyKey)
    }

    private func save(_ value: some Encodable, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            stateLog.error("Could not store \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
