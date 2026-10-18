import AppKit
import SopranoCastCore

/// Fake item icons: square tiles in the app's color with its initial for `.file` icons,
/// dark tiles with a white SF Symbol for `.glyph`, the emoji on a dark tile for `.emoji`.
/// No file system, network or workspace access, so snapshots are deterministic.
@MainActor
final class FixtureIcons: IconProviding {
    private struct CacheKey: Hashable {
        var icon: ItemIcon
        var size: CGFloat
    }

    private var cache: [CacheKey: NSImage] = [:]
    /// Never called: fixture icons are drawn at once, nothing loads later.
    var onLoad: (() -> Void)?

    init() {}

    func image(for icon: ItemIcon, size: CGFloat) -> NSImage {
        let key = CacheKey(icon: icon, size: size)
        if let cached = cache[key] { return cached }
        let image = Self.makeImage(for: icon, size: max(size, 1))
        cache[key] = image
        return image
    }

    private static let pixelScale: CGFloat = 2
    private static let glyphTile: UInt32 = 0x2A2F3D

    private static func makeImage(for icon: ItemIcon, size side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        guard let context = FixtureDrawing.makeContext(pointSize: size, scale: pixelScale) else {
            return NSImage(size: size)
        }
        let rect = CGRect(origin: .zero, size: size)
        FixtureDrawing.withFlippedGraphics(context) {
            switch icon {
            case .file(let path):
                let name = appName(fromPath: path)
                drawTile(rect, color: FixturePalette.color(forName: name), in: context)
                let initial = name.first.map { String($0).uppercased() } ?? "?"
                FixtureDrawing.drawText(
                    initial,
                    font: .systemFont(ofSize: side * 0.56, weight: .bold),
                    color: NSColor.white.withAlphaComponent(0.95),
                    centeredIn: CGRect(x: 0, y: 0, width: side, height: side * 0.9)
                )
            case .emoji(let emoji):
                drawTile(rect, color: FixturePalette.color(hex: glyphTile), in: context)
                FixtureDrawing.drawText(
                    emoji,
                    font: .systemFont(ofSize: side * 0.6),
                    color: .white,
                    centeredIn: rect
                )
            case .glyph(let glyph):
                drawTile(rect, color: FixturePalette.color(hex: glyphTile), in: context)
                drawSymbol(symbolName(for: glyph), fallback: glyph.rawValue, in: rect)
            case .url:
                drawTile(rect, color: FixturePalette.color(hex: glyphTile), in: context)
                drawSymbol(symbolName(for: .link), fallback: "link", in: rect)
            }
        }
        guard let image = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: image, size: size)
    }

    /// "/Applications/Google Chrome.app" → "Google Chrome".
    private static func appName(fromPath path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    private static func drawTile(_ rect: CGRect, color: NSColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
        // A darker band along the bottom gives the flat tile some depth.
        context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        context.fill(CGRect(x: 0, y: rect.height * 0.78, width: rect.width, height: rect.height * 0.22))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(max(1, rect.width / 64))
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }

    /// The symbol in white, 60 % of the tile; the glyph's initial when the symbol is missing.
    /// Requires a flipped current graphics context.
    private static func drawSymbol(_ name: String, fallback: String, in rect: CGRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else {
            FixtureDrawing.drawText(
                fallback.first.map { String($0).uppercased() } ?? "?",
                font: .systemFont(ofSize: rect.height * 0.5, weight: .bold),
                color: .white,
                centeredIn: rect
            )
            return
        }
        let symbolSize = symbol.size
        let fit = min(rect.width * 0.6 / max(symbolSize.width, 1), rect.height * 0.6 / max(symbolSize.height, 1))
        let drawn = CGSize(width: symbolSize.width * fit, height: symbolSize.height * fit)
        let target = CGRect(
            x: rect.midX - drawn.width / 2,
            y: rect.midY - drawn.height / 2,
            width: drawn.width,
            height: drawn.height
        )
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func symbolName(for glyph: BuiltinGlyph) -> String {
        switch glyph {
        case .power: "power"
        case .lock: "lock.fill"
        case .moon: "moon.fill"
        case .display: "display"
        case .trash: "trash.fill"
        case .eject: "eject.fill"
        case .appearance: "circle.lefthalf.filled"
        case .quit: "xmark.circle.fill"
        case .eyeSlash: "eye.slash.fill"
        case .window: "macwindow"
        case .link: "link"
        case .script: "terminal.fill"
        case .gear: "gearshape.fill"
        case .magnifier: "magnifyingglass"
        case .calculator: "plusminus"
        case .refresh: "arrow.clockwise"
        }
    }
}

/// The colors fixture app tiles are drawn in: known apps get a brand-like color,
/// anything else a stable color derived from its name.
enum FixturePalette {
    private static let colorsByName: [String: UInt32] = [
        "Google Chrome": 0x4285F4,
        "Safari": 0x1E88E5,
        "Soprano": 0xFF8019,
        "Soprano Git": 0xE0A526,
        "Soprano Tab": 0xD9662B,
        "Slack": 0x611F69,
        "Mail": 0x2F7BEA,
        "Notes": 0xF2C230,
        "Music": 0xFA3C55,
        "Finder": 0x3FA9F5,
        "System Settings": 0x7A7F87,
        "Xcode": 0x1C7CD6,
        "Aside": 0x2BB673,
        "WhatsApp": 0x25D366,
    ]

    /// Fallback hues for names without an entry, picked by a hash of the name.
    private static let fallback: [UInt32] = [0x2BB673, 0xD9534F, 0x5C6BC0, 0x00897B, 0xC0782F, 0x8E6CC4]

    static func color(forName name: String) -> NSColor {
        if let hex = colorsByName[name] { return color(hex: hex) }
        // FNV-1a over the name: stable across runs, unlike `hashValue`.
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return color(hex: fallback[Int(hash % UInt32(fallback.count))])
    }

    static func color(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Bitmap helpers shared by the fixture icons and the snapshot backdrop.
@MainActor
enum FixtureDrawing {
    /// An sRGB bitmap context of `pointSize × scale` pixels whose user space is points
    /// with a top-left origin (y grows down, like Quartz screen coordinates).
    static func makeContext(pointSize: CGSize, scale: CGFloat) -> CGContext? {
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / max(pointSize.width, 1), y: -CGFloat(height) / max(pointSize.height, 1))
        return context
    }

    /// Runs `draw` with `context` as the current flipped AppKit graphics context, so
    /// `NSString` drawing lands upright in the top-left-origin user space.
    static func withFlippedGraphics(_ context: CGContext, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Draws one line of text centered in `rect`, truncated at the end when too wide.
    /// Requires a flipped current graphics context (`withFlippedGraphics`).
    static func drawText(_ text: String, font: NSFont, color: NSColor, centeredIn rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = ceil(string.size().height)
        let line = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        string.draw(with: line, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
