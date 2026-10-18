import Foundation

/// Selection movement over Root Search's sectioned list, addressed by flat row index.
public enum ResultNavigator {
    /// The new flat selection for a move command over sections with these row counts:
    /// moveUp/moveDown step (no wrap); pageUp/pageDown jump `pageSize`; sectionUp/sectionDown
    /// go to the first row of the previous/next section (sectionUp inside a section goes to its
    /// first row first). nil when there are no rows; other commands return `selected`.
    ///
    /// No selection counts as the first row for every move. Empty sections are skipped.
    public static func move(_ command: LauncherCommand, selected: Int?, rowCounts: [Int], pageSize: Int) -> Int? {
        let total = rowCounts.reduce(0) { $0 + max($1, 0) }
        guard isMove(command) else { return selected }
        guard total > 0 else { return nil }
        guard let selected else { return 0 }
        let current = min(max(selected, 0), total - 1)
        let page = max(pageSize, 1)

        switch command {
        case .moveUp: return max(current - 1, 0)
        case .moveDown: return min(current + 1, total - 1)
        case .pageUp: return max(current - page, 0)
        case .pageDown: return min(current + page, total - 1)
        case .sectionUp:
            let starts = sectionStarts(rowCounts)
            return starts.last { $0 < current } ?? 0
        case .sectionDown:
            let starts = sectionStarts(rowCounts)
            return starts.first { $0 > current } ?? current
        default: return current
        }
    }

    /// Flat index of each non-empty section's first row.
    private static func sectionStarts(_ rowCounts: [Int]) -> [Int] {
        var starts: [Int] = []
        var index = 0
        for count in rowCounts where count > 0 {
            starts.append(index)
            index += count
        }
        return starts
    }

    private static func isMove(_ command: LauncherCommand) -> Bool {
        switch command {
        case .moveUp, .moveDown, .pageUp, .pageDown, .sectionUp, .sectionDown: true
        default: false
        }
    }
}
