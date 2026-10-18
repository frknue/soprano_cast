import AppKit
import ApplicationServices
import SopranoCastCore

/// One display in global Quartz coordinates (top-left origin of the primary display).
struct WindowDisplay: Equatable, Sendable {
    var id: CGDirectDisplayID
    var frame: CGRect
    /// The frame minus the menu bar and the Dock.
    var visible: CGRect
}

/// Where Left/Right Half puts a window under `HalvesBehavior.moveToDisplay`: which half,
/// on which display (an index into the sorted displays).
struct HalfPlacement: Equatable, Sendable {
    var command: WindowCommand
    var display: Int
}

/// Raycast's Window Management on the frontmost app's focused window through Accessibility.
/// The layout math is Core's `WindowLayout`; this class reads the window and the displays,
/// handles the commands that need more than one display or state (fullscreen, restore,
/// previous/next display, halves that move to the neighboring display) and writes the frame.
@MainActor
final class LiveWindowManager: WindowManaging {
    /// How close (points) a window must be to a half to count as already being it.
    nonisolated static let halfTolerance: CGFloat = 2

    /// The frame each window had before the last command that changed it, for `restore`.
    /// Restore itself does not update it, so restoring twice lands on the same frame.
    private var restoreFrames: [CGWindowID: CGRect] = [:]

    init() {}

    func perform(_ command: WindowCommand, settings: WindowManagementSettings) -> String? {
        guard AXIsProcessTrusted() else { return "Window Management needs Accessibility" }
        guard let window = AXWindow.focused(), let frame = window.frame else { return "No focused window" }
        let windowID = window.windowID

        switch command {
        case .toggleFullscreen:
            guard window.supportsFullScreen else { return "This window can't go full screen" }
            window.setFullScreen(!window.isFullScreen)
            return nil
        case .restore:
            guard let windowID, let previous = restoreFrames[windowID] else { return "Nothing to restore" }
            return apply(previous, to: window, currentFrame: frame)
        default:
            break
        }

        let displays = Self.currentDisplays()
        guard let index = Self.display(for: frame, in: displays) else { return "No focused window" }
        guard let target = Self.target(for: command, frame: frame, displays: displays, display: index, settings: settings) else {
            return nil
        }
        if let message = apply(target, to: window, currentFrame: frame) { return message }
        if let windowID, !WindowLayout.matches(frame, target, tolerance: 1) {
            restoreFrames[windowID] = frame
        }
        return nil
    }

    // MARK: - Frames

    /// The new frame for every command except toggleFullscreen and restore; nil when the
    /// command has nothing to do (next display with a single display).
    private static func target(
        for command: WindowCommand, frame: CGRect, displays: [WindowDisplay], display index: Int,
        settings: WindowManagementSettings
    ) -> CGRect? {
        let gap = CGFloat(settings.gap)
        let visible = displays[index].visible
        switch command {
        case .previousDisplay, .nextDisplay:
            let step = command == .nextDisplay ? 1 : -1
            guard let next = adjacentDisplay(from: index, step: step, count: displays.count) else { return nil }
            return WindowLayout.moved(frame, from: visible, to: displays[next].visible)
        case .leftHalf, .rightHalf:
            guard settings.halves == .moveToDisplay else {
                return WindowLayout.frame(for: command, window: frame, visible: visible, gap: gap, halves: settings.halves)
            }
            let half = WindowLayout.frame(for: command, window: frame, visible: visible, gap: gap, halves: .stay)
            let alreadyThere = half.map { WindowLayout.matches(frame, $0, tolerance: halfTolerance) } ?? false
            let placement = moveToDisplayPlacement(for: command, alreadyThere: alreadyThere, display: index, count: displays.count)
            return WindowLayout.frame(
                for: placement.command, window: frame, visible: displays[placement.display].visible, gap: gap, halves: .stay
            )
        default:
            return WindowLayout.frame(for: command, window: frame, visible: visible, gap: gap, halves: settings.halves)
        }
    }

    /// Writes `target`; a message when the window refuses (fixed-size windows can still move).
    private func apply(_ target: CGRect, to window: AXWindow, currentFrame frame: CGRect) -> String? {
        let resizes = abs(target.width - frame.width) > 1 || abs(target.height - frame.height) > 1
        if resizes, !window.isResizable { return "This window can't be resized" }
        guard window.setFrame(target) else { return "This window can't be moved" }
        return nil
    }

    // MARK: - Displays

    /// Every NSScreen in Quartz coordinates, sorted left to right.
    private static func currentDisplays() -> [WindowDisplay] {
        let screens = NSScreen.screens
        // screens[0] is the primary display, whose bottom-left is AppKit's origin.
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return sortedDisplays(screens.map { screen in
            WindowDisplay(
                id: (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0,
                frame: Geometry.quartzRect(fromAppKit: screen.frame, primaryHeight: primaryHeight),
                visible: Geometry.quartzRect(fromAppKit: screen.visibleFrame, primaryHeight: primaryHeight)
            )
        })
    }

    /// Displays ordered by their left edge, then their top edge (Raycast's previous/next
    /// display order: left to right, stacked displays top to bottom).
    nonisolated static func sortedDisplays(_ displays: [WindowDisplay]) -> [WindowDisplay] {
        displays.sorted { lhs, rhs in
            lhs.frame.minX != rhs.frame.minX ? lhs.frame.minX < rhs.frame.minX : lhs.frame.minY < rhs.frame.minY
        }
    }

    /// The index of the display sharing the largest area with `frame` (the first on a tie);
    /// for a window entirely off every display, the display whose center is nearest the
    /// window's center. nil only without displays.
    nonisolated static func display(for frame: CGRect, in displays: [WindowDisplay]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let overlap = display.frame.intersection(frame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if best.map({ area > $0.area }) ?? true { best = (index, area) }
        }
        if let best { return best.index }

        func distance(_ display: WindowDisplay) -> CGFloat {
            let dx = display.frame.midX - frame.midX
            let dy = display.frame.midY - frame.midY
            return dx * dx + dy * dy
        }
        return displays.indices.min { distance(displays[$0]) < distance(displays[$1]) }
    }

    /// The display `step` places from `index`, wrapping around the ends; nil with fewer
    /// than two displays or an index outside them.
    nonisolated static func adjacentDisplay(from index: Int, step: Int, count: Int) -> Int? {
        guard count > 1, (0..<count).contains(index) else { return nil }
        let next = ((index + step) % count + count) % count
        return next == index ? nil : next
    }

    /// Left Half on a window that already is the left half moves it to the right half of
    /// the display to the left; Right Half mirrored. At the outermost display (no wrap) or
    /// when the window isn't that half yet, it stays the plain half on its display. Other
    /// commands pass through.
    nonisolated static func moveToDisplayPlacement(
        for command: WindowCommand, alreadyThere: Bool, display index: Int, count: Int
    ) -> HalfPlacement {
        switch command {
        case .leftHalf where alreadyThere && index > 0:
            HalfPlacement(command: .rightHalf, display: index - 1)
        case .rightHalf where alreadyThere && index + 1 < count:
            HalfPlacement(command: .leftHalf, display: index + 1)
        default:
            HalfPlacement(command: command, display: index)
        }
    }
}
