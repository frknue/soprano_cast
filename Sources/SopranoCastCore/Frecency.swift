import Foundation

/// Frequency + recency of item use, for ranking.
public enum Frecency {
    /// How many uses a record keeps.
    public static let maxUses = 10

    /// Points per use by age in days: the first bucket whose bound the age is below.
    /// Uses dated in the future count as brand new.
    static let buckets: [(maxDays: Double, points: Int)] = [(4, 100), (14, 70), (31, 50), (90, 30)]
    /// Points for a use at least 90 days old.
    static let oldPoints = 10
    static let secondsPerDay: Double = 86_400

    /// Σ over uses of 100 (< 4 days), 70 (< 14), 50 (< 31), 30 (< 90), 10 (older).
    public static func score(_ record: UsageRecord, now: Date) -> Int {
        record.uses.reduce(0) { total, use in
            let days = now.timeIntervalSince(use) / secondsPerDay
            let points = buckets.first(where: { days < $0.maxDays })?.points ?? oldPoints
            return total + points
        }
    }

    /// Adds a use at `date` (newest first, at most 10 kept).
    public static func recording(_ date: Date, in record: UsageRecord?) -> UsageRecord {
        let uses = ([date] + (record?.uses ?? [])).sorted(by: >)
        return UsageRecord(uses: Array(uses.prefix(maxUses)))
    }
}
