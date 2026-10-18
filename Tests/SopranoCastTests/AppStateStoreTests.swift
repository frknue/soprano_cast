import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

@MainActor
struct AppStateStoreTests {
    /// Runs `body` with a fresh suite-named UserDefaults that is removed afterwards.
    private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "com.soprano.cast.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private let chrome = ItemID(rawValue: "app:com.google.Chrome")
    private let leftHalf = ItemID(rawValue: "window:leftHalf")

    @Test("an empty store has no usage and no history")
    func emptyStore() throws {
        try withTemporaryDefaults { defaults in
            let store = AppStateStore(defaults: defaults)

            #expect(store.loadUsage().isEmpty)
            #expect(store.loadHistory().isEmpty)
        }
    }

    @Test("usage and history survive a new store over the same defaults")
    func roundTrip() throws {
        try withTemporaryDefaults { defaults in
            let usage: [ItemID: UsageRecord] = [
                chrome: UsageRecord(uses: [
                    Date(timeIntervalSinceReferenceDate: 780_000_000),
                    Date(timeIntervalSinceReferenceDate: 779_000_000),
                ]),
                leftHalf: UsageRecord(uses: [Date(timeIntervalSinceReferenceDate: 778_500_000)]),
            ]
            let history = ["gc", "left half", "2+2"]

            let writer = AppStateStore(defaults: defaults)
            writer.saveUsage(usage)
            writer.saveHistory(history)
            let reader = AppStateStore(defaults: defaults)

            #expect(reader.loadUsage() == usage)
            #expect(reader.loadHistory() == history)
            #expect(defaults.data(forKey: AppStateStore.usageKey) != nil)
            #expect(defaults.data(forKey: AppStateStore.historyKey) != nil)
        }
    }

    @Test("saving replaces what was stored before")
    func saveReplaces() throws {
        try withTemporaryDefaults { defaults in
            let store = AppStateStore(defaults: defaults)
            store.saveHistory(["old"])
            store.saveUsage([chrome: UsageRecord(uses: [Date(timeIntervalSinceReferenceDate: 1)])])

            store.saveHistory([])
            store.saveUsage([:])

            #expect(store.loadHistory().isEmpty)
            #expect(store.loadUsage().isEmpty)
        }
    }

    @Test("unreadable stored data loads as empty instead of failing")
    func unreadableDataIsEmpty() throws {
        try withTemporaryDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: AppStateStore.usageKey)
            defaults.set(Data("{}".utf8), forKey: AppStateStore.historyKey)
            let store = AppStateStore(defaults: defaults)

            #expect(store.loadUsage().isEmpty)
            #expect(store.loadHistory().isEmpty)
        }
    }
}
