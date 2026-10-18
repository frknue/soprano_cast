import AppKit
import Testing
@testable import SopranoCastCore

struct ResultNavigatorTests {
    private let counts = [3, 0, 4, 2]   // flat rows 0–2, 3–6, 7–8

    private func move(_ command: LauncherCommand, _ selected: Int?, pageSize: Int = 5) -> Int? {
        ResultNavigator.move(command, selected: selected, rowCounts: counts, pageSize: pageSize)
    }

    @Test("moving up and down steps one row without wrapping")
    func stepsWithoutWrap() {
        #expect(move(.moveDown, 0) == 1)
        #expect(move(.moveUp, 4) == 3)
        #expect(move(.moveUp, 0) == 0)
        #expect(move(.moveDown, 8) == 8)
    }

    @Test("moving crosses section boundaries as one flat list")
    func crossesSections() {
        #expect(move(.moveDown, 2) == 3)
        #expect(move(.moveUp, 7) == 6)
    }

    @Test("page jumps move by the page size and clamp at the ends")
    func pages() {
        #expect(move(.pageDown, 1) == 6)
        #expect(move(.pageDown, 6) == 8)
        #expect(move(.pageUp, 7) == 2)
        #expect(move(.pageUp, 3) == 0)
    }

    @Test("section down goes to the next section's first row and stays in the last")
    func sectionDown() {
        #expect(move(.sectionDown, 0) == 3)
        #expect(move(.sectionDown, 5) == 7)
        #expect(move(.sectionDown, 7) == 7)
        #expect(move(.sectionDown, 8) == 8)
    }

    @Test("section up inside a section goes to its first row first, then the previous section")
    func sectionUp() {
        #expect(move(.sectionUp, 5) == 3)
        #expect(move(.sectionUp, 3) == 0)
        #expect(move(.sectionUp, 8) == 7)
        #expect(move(.sectionUp, 1) == 0)
        #expect(move(.sectionUp, 0) == 0)
    }

    @Test("no selection starts at the first row")
    func noSelection() {
        #expect(move(.moveDown, nil) == 0)
        #expect(move(.sectionDown, nil) == 0)
    }

    @Test("an empty list has no selection for every move")
    func emptyList() {
        for command: LauncherCommand in [.moveUp, .moveDown, .pageUp, .pageDown, .sectionUp, .sectionDown] {
            #expect(ResultNavigator.move(command, selected: nil, rowCounts: [], pageSize: 5) == nil)
            #expect(ResultNavigator.move(command, selected: 0, rowCounts: [0, 0], pageSize: 5) == nil)
        }
    }

    @Test("an out-of-range selection is clamped into the list before moving")
    func clampsStaleSelection() {
        #expect(move(.moveDown, 40) == 8)
        #expect(move(.moveUp, 40) == 7)
    }

    @Test("other commands keep the selection")
    func otherCommands() {
        #expect(move(.runPrimary, 4) == 4)
        #expect(move(.historyPrevious, nil) == nil)
        #expect(ResultNavigator.move(.back, selected: 2, rowCounts: [], pageSize: 5) == 2)
    }
}
