import AppKit

/// Soprano Cast's glyph (Folio's Cast `.tpl`): a search field with a lens and a text caret,
/// drawn on a 16-unit grid with a top-left origin, round caps and joins. The menu-bar item
/// uses it at 16 pt with 1.5-unit strokes; the launcher footer's brand mark at 14 pt with 1.4.
enum CastGlyph {
    /// The menu-bar status item's template image.
    static func templateImage() -> NSImage {
        let image = image(side: 16, lineWidth: 1.5, color: .black)
        image.isTemplate = true
        image.accessibilityDescription = "Soprano Cast"
        return image
    }

    /// The glyph in `color`, `side` points square; `lineWidth` is in grid units.
    static func image(side: CGFloat, lineWidth: CGFloat, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: side / 16)
            transform.concat()
            color.setStroke()
            for path in paths() {
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
    }

    /// The field, the lens, its handle and the caret.
    private static func paths() -> [NSBezierPath] {
        let field = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 13, height: 7), xRadius: 3.5, yRadius: 3.5)
        let lens = NSBezierPath(ovalIn: NSRect(x: 5.3 - 1.35, y: 7.7 - 1.35, width: 2.7, height: 2.7))
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: 6.3, y: 8.7))
        handle.line(to: NSPoint(x: 7.2, y: 9.6))
        let caret = NSBezierPath()
        caret.move(to: NSPoint(x: 10.4, y: 6.2))
        caret.line(to: NSPoint(x: 10.4, y: 9.8))
        return [field, lens, handle, caret]
    }
}
