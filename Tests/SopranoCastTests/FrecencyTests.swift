import AppKit
import Testing
@testable import SopranoCastCore

struct FrecencyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    private func points(daysAgo days: Double) -> Int {
        Frecency.score(UsageRecord(uses: [daysAgo(days)]), now: now)
    }

    @Test("each use scores by its age bucket, the bound belonging to the older bucket")
    func buckets() {
        #expect(points(daysAgo: 0) == 100)
        #expect(points(daysAgo: 3.99) == 100)
        #expect(points(daysAgo: 4) == 70)
        #expect(points(daysAgo: 13.99) == 70)
        #expect(points(daysAgo: 14) == 50)
        #expect(points(daysAgo: 30.99) == 50)
        #expect(points(daysAgo: 31) == 30)
        #expect(points(daysAgo: 89.99) == 30)
        #expect(points(daysAgo: 90) == 10)
        #expect(points(daysAgo: 1_000) == 10)
    }

    @Test("a future use counts as brand new and an empty record scores 0")
    func edges() {
        #expect(points(daysAgo: -1) == 100)
        #expect(Frecency.score(UsageRecord(), now: now) == 0)
    }

    @Test("the score sums every use")
    func sum() {
        let record = UsageRecord(uses: [daysAgo(1), daysAgo(5), daysAgo(100)])
        #expect(Frecency.score(record, now: now) == 180)
    }

    @Test("recording puts the new use first and keeps the 10 newest")
    func recording() {
        let first = Frecency.recording(daysAgo(2), in: nil)
        #expect(first.uses == [daysAgo(2)])
        let second = Frecency.recording(daysAgo(1), in: first)
        #expect(second.uses == [daysAgo(1), daysAgo(2)])

        var record: UsageRecord?
        for day in stride(from: 20.0, to: 8.0, by: -1) {
            record = Frecency.recording(daysAgo(day), in: record)
        }
        #expect(record?.uses.count == 10)
        #expect(record?.uses.first == daysAgo(9))
        #expect(record?.uses.last == daysAgo(18))
    }

    @Test("recording an older date keeps the uses sorted newest first")
    func recordingOutOfOrder() {
        let record = Frecency.recording(daysAgo(5), in: UsageRecord(uses: [daysAgo(1), daysAgo(10)]))
        #expect(record.uses == [daysAgo(1), daysAgo(5), daysAgo(10)])
    }
}
