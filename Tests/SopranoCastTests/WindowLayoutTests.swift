import AppKit
import Testing
@testable import SopranoCastCore

struct WindowLayoutTests {
    /// A 1440 × 900 display below a 30 pt menu bar plus a 10 pt Dock, in Quartz coordinates.
    private let visible = CGRect(x: 0, y: 30, width: 1440, height: 860)
    private let window = CGRect(x: 420, y: 260, width: 600, height: 400)

    private func frame(_ command: WindowCommand, window: CGRect? = nil, visible: CGRect? = nil,
                       gap: CGFloat = 0, halves: HalvesBehavior = .stay) -> CGRect? {
        WindowLayout.frame(for: command, window: window ?? self.window, visible: visible ?? self.visible,
                           gap: gap, halves: halves)
    }

    private func frames(_ commands: [WindowCommand], visible: CGRect, gap: CGFloat) -> [CGRect] {
        commands.compactMap { frame($0, visible: visible, gap: gap) }
    }

    private func isIntegral(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0 == $0.rounded() }
    }

    /// Regions that cover `bounds` exactly: inside it, no overlaps, areas adding up.
    private func tiles(_ regions: [CGRect], _ bounds: CGRect) -> Bool {
        guard regions.allSatisfy({ bounds.contains($0) && isIntegral($0) }) else { return false }
        for (i, a) in regions.enumerated() {
            for b in regions[(i + 1)...] {
                let overlap = a.intersection(b)
                if !overlap.isNull && overlap.width > 0 && overlap.height > 0 { return false }
            }
        }
        return regions.reduce(0) { $0 + $1.width * $1.height } == bounds.width * bounds.height
    }

    /// One row of regions: `gap` from the outer edges and exactly `gap` between neighbors.
    private func spaced(_ row: [CGRect], _ bounds: CGRect, gap: CGFloat) -> Bool {
        let sorted = row.sorted { $0.minX < $1.minX }
        guard let first = sorted.first, let last = sorted.last else { return false }
        guard first.minX == bounds.minX + gap, last.maxX == bounds.maxX - gap else { return false }
        return zip(sorted, sorted.dropFirst()).allSatisfy { $1.minX - $0.maxX == gap }
    }

    static let groups: [[WindowCommand]] = [
        [.leftHalf, .rightHalf],
        [.topHalf, .bottomHalf],
        [.firstThird, .centerThird, .lastThird],
        [.firstTwoThirds, .lastThird],
        [.firstThird, .lastTwoThirds],
        [.firstFourth, .secondFourth, .thirdFourth, .lastFourth],
        [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter],
        [.topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth],
    ]

    @Test("without a gap, halves, thirds, fourths, quarters and sixths tile the visible frame exactly")
    func tilingWithoutGap() {
        let odd = CGRect(x: -1437, y: -200, width: 1437, height: 875)
        for group in Self.groups {
            #expect(tiles(frames(group, visible: visible, gap: 0), visible), "\(group)")
            #expect(tiles(frames(group, visible: odd, gap: 0), odd), "\(group) on odd frame")
        }
    }

    @Test("halves, thirds and quarters land on the expected frames")
    func exactRegions() {
        #expect(frame(.leftHalf) == CGRect(x: 0, y: 30, width: 720, height: 860))
        #expect(frame(.rightHalf) == CGRect(x: 720, y: 30, width: 720, height: 860))
        #expect(frame(.topHalf) == CGRect(x: 0, y: 30, width: 1440, height: 430))
        #expect(frame(.bottomHalf) == CGRect(x: 0, y: 460, width: 1440, height: 430))
        #expect(frame(.centerThird) == CGRect(x: 480, y: 30, width: 480, height: 860))
        #expect(frame(.lastTwoThirds) == CGRect(x: 480, y: 30, width: 960, height: 860))
        #expect(frame(.secondFourth) == CGRect(x: 360, y: 30, width: 360, height: 860))
        #expect(frame(.bottomRightQuarter) == CGRect(x: 720, y: 460, width: 720, height: 430))
        #expect(frame(.topCenterSixth) == CGRect(x: 480, y: 30, width: 480, height: 430))
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        #expect(frame(.leftHalf, visible: second) == CGRect(x: 1440, y: -200, width: 960, height: 1055))
    }

    @Test("a gap separates regions from the display edges and from each other by exactly g")
    func tilingWithGap() {
        #expect(frame(.leftHalf, gap: 10) == CGRect(x: 10, y: 40, width: 705, height: 840))
        #expect(frame(.rightHalf, gap: 10) == CGRect(x: 725, y: 40, width: 705, height: 840))
        let inner = visible.insetBy(dx: 10, dy: 10)
        let rows: [[WindowCommand]] = [
            [.leftHalf, .rightHalf],
            [.firstThird, .centerThird, .lastThird],
            [.firstTwoThirds, .lastThird],
            [.firstFourth, .secondFourth, .thirdFourth, .lastFourth],
            [.topLeftQuarter, .topRightQuarter],
            [.bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth],
        ]
        for row in rows {
            let regions = frames(row, visible: visible, gap: 10)
            #expect(spaced(regions, visible, gap: 10), "\(row)")
            #expect(regions.allSatisfy { inner.contains($0) && isIntegral($0) }, "\(row)")
        }
        let top = frame(.topHalf, gap: 10)!, bottom = frame(.bottomHalf, gap: 10)!
        #expect(top.minY == 40)
        #expect(bottom.minY - top.maxY == 10)
        #expect(bottom.maxY == 880)
    }

    @Test("maximize fills the visible frame minus the gap; height and width keep the other axis")
    func maximize() {
        #expect(frame(.maximize) == visible)
        #expect(frame(.maximize, gap: 8) == CGRect(x: 8, y: 38, width: 1424, height: 844))
        #expect(frame(.maximizeHeight) == CGRect(x: 420, y: 30, width: 600, height: 860))
        #expect(frame(.maximizeWidth) == CGRect(x: 0, y: 260, width: 1440, height: 400))
        #expect(frame(.maximizeHeight, gap: 10) == CGRect(x: 420, y: 40, width: 600, height: 840))
    }

    @Test("almost maximize is 90 % centered and center half is half width at full height")
    func centeredSizes() {
        #expect(frame(.almostMaximize) == CGRect(x: 72, y: 73, width: 1296, height: 774))
        #expect(frame(.centerHalf) == CGRect(x: 360, y: 30, width: 720, height: 860))
        #expect(frame(.centerHalf, gap: 10) == CGRect(x: 368, y: 40, width: 705, height: 840))
    }

    @Test("reasonable size is 60 % of each side, capped at 1025 × 900, centered")
    func reasonableSize() {
        #expect(frame(.reasonableSize) == CGRect(x: 288, y: 202, width: 864, height: 516))
        let large = CGRect(x: 0, y: 0, width: 2560, height: 2000)
        #expect(frame(.reasonableSize, visible: large) == CGRect(x: 768, y: 550, width: 1025, height: 900))
    }

    @Test("center keeps the size and clamps windows larger than the visible frame")
    func center() {
        let offset = CGRect(x: 3, y: 700, width: 600, height: 400)
        #expect(frame(.center, window: offset) == CGRect(x: 420, y: 260, width: 600, height: 400))
        let huge = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        #expect(frame(.center, window: huge, gap: 10) == CGRect(x: 10, y: 40, width: 1420, height: 840))
    }

    @Test("moves keep the size and touch one edge, leaving the other coordinate alone")
    func moves() {
        let start = CGRect(x: 300, y: 500, width: 600, height: 400)
        #expect(frame(.moveUp, window: start) == CGRect(x: 300, y: 30, width: 600, height: 400))
        #expect(frame(.moveUp, window: start, gap: 10) == CGRect(x: 300, y: 40, width: 600, height: 400))
        #expect(frame(.moveDown, window: start, gap: 10) == CGRect(x: 300, y: 480, width: 600, height: 400))
        #expect(frame(.moveLeft, window: start, gap: 10) == CGRect(x: 10, y: 500, width: 600, height: 400))
        #expect(frame(.moveRight, window: start, gap: 10) == CGRect(x: 830, y: 500, width: 600, height: 400))
        #expect(frame(.moveRight, window: start) == CGRect(x: 840, y: 500, width: 600, height: 400))
    }

    @Test("make larger and smaller step by 10 % of the display around the window center")
    func resizeSteps() {
        #expect(frame(.makeLarger) == CGRect(x: 348, y: 217, width: 744, height: 486))
        #expect(frame(.makeSmaller) == CGRect(x: 492, y: 303, width: 456, height: 314))
    }

    @Test("make larger stops at the visible frame and make smaller at 200 × 150")
    func resizeLimits() {
        let nearlyFull = CGRect(x: 0, y: 30, width: 1400, height: 800)
        #expect(frame(.makeLarger, window: nearlyFull) == visible)
        #expect(frame(.makeLarger, window: nearlyFull, gap: 10) == visible.insetBy(dx: 10, dy: 10))
        let small = CGRect(x: 600, y: 400, width: 250, height: 160)
        #expect(frame(.makeSmaller, window: small) == CGRect(x: 625, y: 405, width: 200, height: 150))
        let minimum = CGRect(x: 600, y: 400, width: 200, height: 150)
        #expect(frame(.makeSmaller, window: minimum) == minimum)
    }

    @Test("cycling halves steps ½ → ⅔ → ⅓ → ½ when the window already is the current step")
    func cycleSizes() {
        var current = window
        var lefts: [CGRect] = []
        for _ in 0..<4 {
            current = frame(.leftHalf, window: current, halves: .cycleSizes)!
            lefts.append(current)
        }
        #expect(lefts == [
            CGRect(x: 0, y: 30, width: 720, height: 860),
            CGRect(x: 0, y: 30, width: 960, height: 860),
            CGRect(x: 0, y: 30, width: 480, height: 860),
            CGRect(x: 0, y: 30, width: 720, height: 860),
        ])
        let right = CGRect(x: 720, y: 30, width: 720, height: 860)
        #expect(frame(.rightHalf, window: right, halves: .cycleSizes) == CGRect(x: 480, y: 30, width: 960, height: 860))
        #expect(frame(.rightHalf, window: CGRect(x: 480, y: 30, width: 960, height: 860), halves: .cycleSizes)
            == CGRect(x: 960, y: 30, width: 480, height: 860))
    }

    @Test("cycling tolerates 2 pt of drift, and other halves settings keep the plain half")
    func cycleTolerance() {
        let half = CGRect(x: 0, y: 30, width: 720, height: 860)
        let nearly = CGRect(x: 1, y: 31, width: 718, height: 859)
        #expect(frame(.leftHalf, window: nearly, halves: .cycleSizes)?.width == 960)
        let off = CGRect(x: 3, y: 30, width: 720, height: 860)
        #expect(frame(.leftHalf, window: off, halves: .cycleSizes) == half)
        #expect(frame(.leftHalf, window: half, halves: .stay) == half)
        #expect(frame(.leftHalf, window: half, halves: .moveToDisplay) == half)
    }

    @Test("fullscreen, restore and display moves are left to the window manager")
    func managerCommands() {
        for command in [WindowCommand.toggleFullscreen, .restore, .previousDisplay, .nextDisplay] {
            #expect(frame(command) == nil, "\(command)")
        }
        let handled = WindowCommand.allCases.filter { frame($0) != nil }
        #expect(handled.count == WindowCommand.allCases.count - 4)
        #expect(handled.allSatisfy { isIntegral(frame($0, gap: 7)!) })
    }

    @Test("moving between displays keeps the relative position and size")
    func movedKeeps() {
        let source = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(WindowLayout.moved(CGRect(x: 144, y: 90, width: 720, height: 450), from: source, to: target)
            == CGRect(x: 1632, y: 108, width: 720, height: 450))
    }

    @Test("moving to a smaller display scales the window down and clamps it inside")
    func movedScalesAndClamps() {
        let source = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let smaller = CGRect(x: 1440, y: 0, width: 720, height: 450)
        #expect(WindowLayout.moved(CGRect(x: 144, y: 90, width: 720, height: 450), from: source, to: smaller)
            == CGRect(x: 1512, y: 45, width: 360, height: 225))
        let sameSize = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        #expect(WindowLayout.moved(CGRect(x: 1300, y: 800, width: 400, height: 300), from: source, to: sameSize)
            == CGRect(x: 2480, y: 600, width: 400, height: 300))
    }

    @Test("matches compares origin and size within the tolerance")
    func matches() {
        let a = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(WindowLayout.matches(a, CGRect(x: 12, y: 8, width: 98, height: 102), tolerance: 2))
        #expect(!WindowLayout.matches(a, CGRect(x: 13, y: 10, width: 100, height: 100), tolerance: 2))
        #expect(!WindowLayout.matches(a, CGRect(x: 10, y: 10, width: 100, height: 97), tolerance: 2))
        #expect(WindowLayout.matches(a, a, tolerance: 0))
    }
}
