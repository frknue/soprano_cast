import AppKit
import Testing
@testable import SopranoCast

@MainActor
struct CastGlyphTests {
    @Test("the menu-bar glyph is a 16 pt template image")
    func templateImage() {
        let image = CastGlyph.templateImage()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.accessibilityDescription == "Soprano Cast")
    }

    @Test("the glyph strokes the field outline and leaves its middle and corners clear")
    func drawsTheField() throws {
        let image = CastGlyph.image(side: 16, lineWidth: 1.5, color: .black)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        // Pixel rows count from the top: the field's top edge runs along y = 4.5 (pixel row 9).
        #expect(alpha(16, 9) > 0.5)
        #expect(alpha(25, 16) == 0)
        #expect(alpha(2, 2) == 0)
    }
}
