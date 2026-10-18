import AppKit
import Testing
@testable import SopranoCast
@testable import SopranoCastCore

struct WindowDisplayTests {
    /// Quartz coordinates: a 1920 × 1080 display left of the 1512 × 982 primary, raised
    /// 200 pt, and a 1080 × 1920 portrait display to its right.
    private let left = WindowDisplay(
        id: 2, frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
        visible: CGRect(x: -1920, y: -175, width: 1920, height: 1055)
    )
    private let primary = WindowDisplay(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visible: CGRect(x: 0, y: 38, width: 1512, height: 944)
    )
    private let right = WindowDisplay(
        id: 3, frame: CGRect(x: 1512, y: -400, width: 1080, height: 1920),
        visible: CGRect(x: 1512, y: -375, width: 1080, height: 1895)
    )

    private var arranged: [WindowDisplay] { [left, primary, right] }

    // MARK: - Sorting

    @Test("displays sort left to right by their left edge")
    func sortsByLeftEdge() {
        #expect(LiveWindowManager.sortedDisplays([right, primary, left]) == [left, primary, right])
    }

    @Test("displays sharing a left edge sort top to bottom")
    func stackedDisplaysSortByTopEdge() {
        let above = WindowDisplay(
            id: 4, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            visible: CGRect(x: 0, y: -1055, width: 1920, height: 1055)
        )
        #expect(LiveWindowManager.sortedDisplays([primary, above]) == [above, primary])
    }

    // MARK: - Display of a window

    @Test("a window belongs to the display holding most of it")
    func largestOverlapWins() {
        // 300 pt on the left display, 500 pt on the primary.
        let window = CGRect(x: -300, y: 100, width: 800, height: 600)
        #expect(LiveWindowManager.display(for: window, in: arranged) == 1)
        // 600 pt on the left display, 200 pt on the primary.
        let mostlyLeft = CGRect(x: -600, y: 100, width: 800, height: 600)
        #expect(LiveWindowManager.display(for: mostlyLeft, in: arranged) == 0)
    }

    @Test("a window split evenly between two displays belongs to the first")
    func tieGoesToFirstDisplay() {
        let window = CGRect(x: -400, y: 100, width: 800, height: 600)
        #expect(LiveWindowManager.display(for: window, in: arranged) == 0)
    }

    @Test("a window off every display belongs to the nearest one")
    func offscreenWindowUsesNearestDisplay() {
        let farRight = CGRect(x: 5000, y: 200, width: 400, height: 300)
        #expect(LiveWindowManager.display(for: farRight, in: arranged) == 2)
        let below = CGRect(x: 500, y: 3000, width: 400, height: 300)
        #expect(LiveWindowManager.display(for: below, in: arranged) == 1)
    }

    @Test("without displays there is no display")
    func noDisplays() {
        #expect(LiveWindowManager.display(for: CGRect(x: 0, y: 0, width: 100, height: 100), in: []) == nil)
    }

    // MARK: - Previous / next display

    @Test("next and previous display step one place")
    func adjacentSteps() {
        #expect(LiveWindowManager.adjacentDisplay(from: 0, step: 1, count: 3) == 1)
        #expect(LiveWindowManager.adjacentDisplay(from: 2, step: -1, count: 3) == 1)
    }

    @Test("next display wraps from the last to the first and previous the other way")
    func adjacentWraps() {
        #expect(LiveWindowManager.adjacentDisplay(from: 2, step: 1, count: 3) == 0)
        #expect(LiveWindowManager.adjacentDisplay(from: 0, step: -1, count: 3) == 2)
    }

    @Test("with a single display there is nowhere to move")
    func singleDisplayHasNoNeighbor() {
        #expect(LiveWindowManager.adjacentDisplay(from: 0, step: 1, count: 1) == nil)
        #expect(LiveWindowManager.adjacentDisplay(from: 0, step: -1, count: 1) == nil)
    }

    @Test("with two displays next and previous both reach the other one")
    func twoDisplaysToggle() {
        #expect(LiveWindowManager.adjacentDisplay(from: 0, step: 1, count: 2) == 1)
        #expect(LiveWindowManager.adjacentDisplay(from: 0, step: -1, count: 2) == 1)
        #expect(LiveWindowManager.adjacentDisplay(from: 1, step: 1, count: 2) == 0)
    }

    @Test("an index outside the displays has no neighbor")
    func outOfRangeIndex() {
        #expect(LiveWindowManager.adjacentDisplay(from: 3, step: 1, count: 3) == nil)
        #expect(LiveWindowManager.adjacentDisplay(from: -1, step: 1, count: 3) == nil)
    }

    // MARK: - Halves that move to the next display

    @Test("left half on a window that is not the left half yet stays on its display")
    func firstLeftHalfStays() {
        let placement = LiveWindowManager.moveToDisplayPlacement(for: .leftHalf, alreadyThere: false, display: 1, count: 3)
        #expect(placement == HalfPlacement(command: .leftHalf, display: 1))
    }

    @Test("left half again moves the window to the right half of the display to the left")
    func repeatedLeftHalfMovesLeft() {
        let placement = LiveWindowManager.moveToDisplayPlacement(for: .leftHalf, alreadyThere: true, display: 1, count: 3)
        #expect(placement == HalfPlacement(command: .rightHalf, display: 0))
    }

    @Test("right half again moves the window to the left half of the display to the right")
    func repeatedRightHalfMovesRight() {
        let placement = LiveWindowManager.moveToDisplayPlacement(for: .rightHalf, alreadyThere: true, display: 1, count: 3)
        #expect(placement == HalfPlacement(command: .leftHalf, display: 2))
    }

    @Test("halves don't wrap past the outermost displays")
    func halvesStopAtTheEdges() {
        let leftmost = LiveWindowManager.moveToDisplayPlacement(for: .leftHalf, alreadyThere: true, display: 0, count: 3)
        #expect(leftmost == HalfPlacement(command: .leftHalf, display: 0))
        let rightmost = LiveWindowManager.moveToDisplayPlacement(for: .rightHalf, alreadyThere: true, display: 2, count: 3)
        #expect(rightmost == HalfPlacement(command: .rightHalf, display: 2))
    }

    @Test("other commands keep their display")
    func otherCommandsPassThrough() {
        let placement = LiveWindowManager.moveToDisplayPlacement(for: .topHalf, alreadyThere: true, display: 1, count: 3)
        #expect(placement == HalfPlacement(command: .topHalf, display: 1))
    }
}
