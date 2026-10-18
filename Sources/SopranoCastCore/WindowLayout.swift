import CoreGraphics

/// Window management math in global Quartz coordinates (top-left origin, y down).
///
/// Window rules: halves/thirds/fourths/quarters/sixths split the visible frame into equal
/// regions; maximize fills it (minus gaps); almostMaximize = 90 % centered; maximizeHeight /
/// maximizeWidth keep the other axis; reasonableSize = 60 % of each side capped at 1025 × 900,
/// centered; center keeps the size (clamped), centered; centerHalf = half width, full height,
/// centered; moveUp/Down/Left/Right keep the size (clamped) and touch that edge (with gap),
/// centered along it (Raycast's "Center Window" option); makeLarger/makeSmaller grow/shrink
/// by 10 % of the visible size around the window center, clamped to the visible frame, at
/// least 200 × 150.
public enum WindowLayout {
    /// The target frame (global Quartz coordinates) for `command` on a window at `frame` on a
    /// display whose visible frame is `visible`. Gap g: g at display edges and between
    /// regions. nil for toggleFullscreen, restore, previousDisplay, nextDisplay (the window
    /// manager handles those). `halves: .cycleSizes` cycles Left/Right Half ½ → ⅔ → ⅓ → ½
    /// when the window already is (±2 pt) the current step; `.moveToDisplay` is the window
    /// manager's (this returns the plain half). Frames are integral.
    public static func frame(for command: WindowCommand, window frame: CGRect, visible: CGRect, gap: CGFloat, halves: HalvesBehavior) -> CGRect? {
        let g = max(0, gap)
        let inner = visible.insetBy(dx: g, dy: g)
        func columns(_ count: Int, _ column: Int, span: Int = 1) -> CGRect {
            region(visible, gap: g, columns: count, column: column, span: span, rows: 1, row: 0)
        }
        func grid(columns count: Int, rows: Int, _ column: Int, _ row: Int) -> CGRect {
            region(visible, gap: g, columns: count, column: column, span: 1, rows: rows, row: row)
        }

        switch command {
        case .toggleFullscreen, .restore, .previousDisplay, .nextDisplay:
            return nil
        case .maximize:
            return edges(inner.minX, inner.minY, inner.maxX, inner.maxY)
        case .almostMaximize:
            return centered(CGSize(width: visible.width * 0.9, height: visible.height * 0.9), in: visible)
        case .maximizeHeight:
            return edges(frame.minX, inner.minY, frame.maxX, inner.maxY)
        case .maximizeWidth:
            return edges(inner.minX, frame.minY, inner.maxX, frame.maxY)
        case .leftHalf:
            let steps = [columns(2, 0), columns(3, 0, span: 2), columns(3, 0)]
            return halves == .cycleSizes ? nextStep(steps, window: frame) : steps[0]
        case .rightHalf:
            let steps = [columns(2, 1), columns(3, 1, span: 2), columns(3, 2)]
            return halves == .cycleSizes ? nextStep(steps, window: frame) : steps[0]
        case .topHalf:
            return grid(columns: 1, rows: 2, 0, 0)
        case .bottomHalf:
            return grid(columns: 1, rows: 2, 0, 1)
        case .centerHalf:
            let half = columns(2, 0)
            let x = (visible.midX - half.width / 2).rounded()
            return CGRect(x: x, y: half.minY, width: half.width, height: half.height)
        case .center:
            return centered(fitted(frame.size, in: inner), in: visible)
        case .moveUp, .moveDown, .moveLeft, .moveRight:
            let size = fitted(frame.size, in: inner)
            var origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
            switch command {
            case .moveUp: origin.y = inner.minY
            case .moveDown: origin.y = inner.maxY - size.height
            case .moveLeft: origin.x = inner.minX
            default: origin.x = inner.maxX - size.width
            }
            return rounded(CGRect(origin: origin, size: size))
        case .reasonableSize:
            let size = CGSize(width: min(visible.width * 0.6, 1025), height: min(visible.height * 0.6, 900))
            return centered(size, in: visible)
        case .makeLarger, .makeSmaller:
            let sign: CGFloat = command == .makeLarger ? 1 : -1
            let minimum = CGSize(width: min(200, inner.width), height: min(150, inner.height))
            let size = CGSize(
                width: min(max(frame.width + sign * visible.width * 0.1, minimum.width), inner.width),
                height: min(max(frame.height + sign * visible.height * 0.1, minimum.height), inner.height)
            )
            let resized = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                 width: size.width, height: size.height)
            return clamped(resized, in: inner)
        case .firstThird: return columns(3, 0)
        case .firstTwoThirds: return columns(3, 0, span: 2)
        case .centerThird: return columns(3, 1)
        case .lastTwoThirds: return columns(3, 1, span: 2)
        case .lastThird: return columns(3, 2)
        case .firstFourth: return columns(4, 0)
        case .secondFourth: return columns(4, 1)
        case .thirdFourth: return columns(4, 2)
        case .lastFourth: return columns(4, 3)
        case .topLeftQuarter: return grid(columns: 2, rows: 2, 0, 0)
        case .topRightQuarter: return grid(columns: 2, rows: 2, 1, 0)
        case .bottomLeftQuarter: return grid(columns: 2, rows: 2, 0, 1)
        case .bottomRightQuarter: return grid(columns: 2, rows: 2, 1, 1)
        case .topLeftSixth: return grid(columns: 3, rows: 2, 0, 0)
        case .topCenterSixth: return grid(columns: 3, rows: 2, 1, 0)
        case .topRightSixth: return grid(columns: 3, rows: 2, 2, 0)
        case .bottomLeftSixth: return grid(columns: 3, rows: 2, 0, 1)
        case .bottomCenterSixth: return grid(columns: 3, rows: 2, 1, 1)
        case .bottomRightSixth: return grid(columns: 3, rows: 2, 2, 1)
        }
    }

    /// `frame` moved from `source` to `target` visible frames keeping its relative position
    /// (its center lands on the same relative point of `target`) and its aspect ratio
    /// (Raycast's "Keep Aspect Ratio"): the size scales by one factor, the smaller of the two
    /// display ratios when the target is smaller, further reduced until it fits `target`,
    /// never above 1. Clamped inside `target`; integral.
    public static func moved(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return clamped(frame, in: target) }
        var scale: CGFloat = 1
        if source.width > 0, source.height > 0 {
            scale = min(scale, target.width / source.width, target.height / source.height)
        }
        scale = min(scale, target.width / frame.width, target.height / frame.height)
        let size = CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
        let relativeX = source.width > 0 ? (frame.midX - source.minX) / source.width : 0.5
        let relativeY = source.height > 0 ? (frame.midY - source.minY) / source.height : 0.5
        let center = CGPoint(x: target.minX + relativeX * target.width, y: target.minY + relativeY * target.height)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return clamped(CGRect(origin: origin, size: size), in: target)
    }

    /// Whether `frame` equals `expected` within `tolerance`.
    public static func matches(_ frame: CGRect, _ expected: CGRect, tolerance: CGFloat) -> Bool {
        abs(frame.minX - expected.minX) <= tolerance
            && abs(frame.minY - expected.minY) <= tolerance
            && abs(frame.width - expected.width) <= tolerance
            && abs(frame.height - expected.height) <= tolerance
    }

    /// How close a window must be to a cycle step to count as already being it.
    static let cycleTolerance: CGFloat = 2

    /// The step after the one the window already is; the first step otherwise.
    private static func nextStep(_ steps: [CGRect], window: CGRect) -> CGRect {
        guard let current = steps.firstIndex(where: { matches(window, $0, tolerance: cycleTolerance) }) else {
            return steps[0]
        }
        return steps[(current + 1) % steps.count]
    }

    /// Cell `column`…`column + span - 1` of row `row` in an equal grid with `gap` around and
    /// between cells. Edges are rounded individually so neighbors stay exactly `gap` apart.
    private static func region(_ visible: CGRect, gap: CGFloat, columns: Int, column: Int, span: Int, rows: Int, row: Int) -> CGRect {
        let cellWidth = (visible.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let cellHeight = (visible.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        let minX = visible.minX + gap + CGFloat(column) * (cellWidth + gap)
        let maxX = visible.minX + gap + CGFloat(column + span) * (cellWidth + gap) - gap
        let minY = visible.minY + gap + CGFloat(row) * (cellHeight + gap)
        let maxY = visible.minY + gap + CGFloat(row + 1) * (cellHeight + gap) - gap
        return edges(minX, minY, maxX, maxY)
    }

    private static func edges(_ minX: CGFloat, _ minY: CGFloat, _ maxX: CGFloat, _ maxY: CGFloat) -> CGRect {
        let left = minX.rounded(), top = minY.rounded()
        return CGRect(x: left, y: top, width: maxX.rounded() - left, height: maxY.rounded() - top)
    }

    /// `size` no larger than `bounds`.
    private static func fitted(_ size: CGSize, in bounds: CGRect) -> CGSize {
        CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
    }

    private static func centered(_ size: CGSize, in bounds: CGRect) -> CGRect {
        let width = size.width.rounded(), height = size.height.rounded()
        return CGRect(x: (bounds.midX - width / 2).rounded(), y: (bounds.midY - height / 2).rounded(),
                      width: width, height: height)
    }

    /// Integral `rect`, shrunk to fit `bounds` and shifted inside them.
    private static func clamped(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let width = min(rect.width.rounded(), bounds.width.rounded(.down))
        let height = min(rect.height.rounded(), bounds.height.rounded(.down))
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width).rounded()
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height).rounded()
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }
}
