import AppKit
import CryptoKit
import OSLog
import SopranoCastCore
import UniformTypeIdentifiers

private let iconLog = Logger(subsystem: "com.soprano.cast", category: "icons")

/// Item icons: Finder icons of files and bundles, image files as themselves, emoji drawn
/// into an image, built-in glyphs as SF Symbols in the theme accent on a raised tile, and
/// remote icons downloaded once into the Caches folder. Everything is cached per (icon,
/// size); glyph tiles also per theme.
@MainActor
final class LiveIconProvider: IconProviding {
    private struct CacheKey: Hashable {
        var icon: ItemIcon
        var size: CGFloat
        /// Only for glyphs, whose colors come from the theme.
        var themeID: String?
    }

    /// Where remote icons are kept between launches.
    nonisolated static let remoteCacheFolder = "com.soprano.cast/icons"

    var onLoad: (() -> Void)?

    private let theme: @MainActor () -> AppTheme
    private var cache: [CacheKey: NSImage] = [:]
    private var downloading: Set<URL> = []
    /// Remote icons that could not be loaded this session; they keep the placeholder.
    private var failedDownloads: Set<URL> = []

    init(theme: @escaping @MainActor () -> AppTheme) {
        self.theme = theme
    }

    func image(for icon: ItemIcon, size: CGFloat) -> NSImage {
        var key = CacheKey(icon: icon, size: size)
        if case .glyph = icon { key.themeID = theme().id }
        if let image = cache[key] { return image }
        let image: NSImage
        switch icon {
        case .file(let path):
            image = fileImage(path: path, size: size)
        case .emoji(let emoji):
            image = Self.emojiImage(emoji, size: size)
        case .glyph(let glyph):
            image = glyphImage(glyph, size: size)
        case .url(let url):
            guard let cached = remoteImage(url, size: size) else {
                // Not cached under the URL: the real icon replaces the placeholder once loaded.
                return self.image(for: .glyph(.script), size: size)
            }
            image = cached
        }
        cache[key] = image
        return image
    }

    // MARK: - Files

    /// Image files (script icons like "icon.png") show their picture; anything else its
    /// Finder icon.
    private func fileImage(path: String, size: CGFloat) -> NSImage {
        let image: NSImage
        if Self.isImageFile(path), let picture = NSImage(contentsOfFile: path) {
            image = picture
        } else {
            image = NSWorkspace.shared.icon(forFile: path)
        }
        image.size = NSSize(width: size, height: size)
        return image
    }

    nonisolated private static func isImageFile(_ path: String) -> Bool {
        let pathExtension = (path as NSString).pathExtension
        guard !pathExtension.isEmpty, let type = UTType(filenameExtension: pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    // MARK: - Emoji

    private static func emojiImage(_ emoji: String, size: CGFloat) -> NSImage {
        render(size: size) { rect in
            let font = NSFont.systemFont(ofSize: size * 0.8)
            let text = NSAttributedString(string: emoji, attributes: [.font: font])
            let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
            text.draw(at: NSPoint(
                x: rect.midX - bounds.width / 2 - bounds.minX,
                y: rect.midY - bounds.height / 2 - bounds.minY
            ))
        }
    }

    // MARK: - Glyphs

    nonisolated static func symbolName(for glyph: BuiltinGlyph) -> String {
        switch glyph {
        case .power: "power"
        case .lock: "lock.fill"
        case .moon: "moon.fill"
        case .display: "display"
        case .trash: "trash.fill"
        case .eject: "eject.fill"
        case .appearance: "circle.lefthalf.filled"
        case .quit: "xmark.square"
        case .eyeSlash: "eye.slash"
        case .window: "macwindow"
        case .link: "link"
        case .script: "terminal"
        case .gear: "gearshape"
        case .magnifier: "magnifyingglass"
        case .calculator: "function"
        case .refresh: "arrow.clockwise"
        }
    }

    /// The symbol in the accent, centered on a square `bgRaised` tile.
    private func glyphImage(_ glyph: BuiltinGlyph, size: CGFloat) -> NSImage {
        let colors = theme().colors
        let configuration = NSImage.SymbolConfiguration(pointSize: (size * 0.5).rounded(), weight: .medium)
        let symbol = NSImage(systemSymbolName: Self.symbolName(for: glyph), accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let tinted = symbol.map { Self.tinted($0, color: colors.accent) }
        return Self.render(size: size) { rect in
            colors.bgRaised.setFill()
            rect.fill()
            guard let tinted else { return }
            let inset = size * 0.2
            let available = rect.insetBy(dx: inset, dy: inset)
            let scale = min(1, available.width / tinted.size.width, available.height / tinted.size.height)
            let width = tinted.size.width * scale
            let height = tinted.size.height * scale
            tinted.draw(in: NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
        }
    }

    /// `symbol` (a template image) filled with `color`.
    private static func tinted(_ symbol: NSImage, color: NSColor) -> NSImage {
        let size = symbol.size
        let image = render(width: size.width, height: size.height) { rect in
            symbol.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
        }
        return image
    }

    // MARK: - Remote icons

    /// The downloaded icon, or nil after starting (or while waiting for) its download.
    private func remoteImage(_ url: URL, size: CGFloat) -> NSImage? {
        guard let file = Self.cacheFile(for: url) else { return nil }
        if let image = NSImage(contentsOf: file) {
            image.size = NSSize(width: size, height: size)
            return image
        }
        download(url, to: file)
        return nil
    }

    private func download(_ url: URL, to file: URL) {
        guard !downloading.contains(url), !failedDownloads.contains(url) else { return }
        downloading.insert(url)
        Task { [weak self] in
            let loaded = await Self.fetch(url, to: file)
            guard let self else { return }
            downloading.remove(url)
            if loaded {
                onLoad?()
            } else {
                failedDownloads.insert(url)
            }
        }
    }

    /// Downloads `url` and writes it to `file` when it is an image.
    nonisolated private static func fetch(_ url: URL, to file: URL) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                iconLog.error("Icon \(url.absoluteString, privacy: .public) answered \(http.statusCode)")
                return false
            }
            guard NSImage(data: data) != nil else {
                iconLog.error("Icon \(url.absoluteString, privacy: .public) is not an image")
                return false
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            iconLog.error("Loading icon \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// `~/Library/Caches/com.soprano.cast/icons/<sha256 of the URL>[.ext]`.
    nonisolated private static func cacheFile(for url: URL) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let pathExtension = url.pathExtension.lowercased()
        let name = pathExtension.isEmpty || pathExtension.count > 5 ? digest : "\(digest).\(pathExtension)"
        return caches.appendingPathComponent(remoteCacheFolder, isDirectory: true).appendingPathComponent(name)
    }

    // MARK: - Drawing

    private static func render(size: CGFloat, _ draw: (NSRect) -> Void) -> NSImage {
        render(width: size, height: size, draw)
    }

    /// Draws into a bitmap at the highest screen scale (at least 2×), sized in points.
    private static func render(width: CGFloat, height: CGFloat, _ draw: (NSRect) -> Void) -> NSImage {
        let pointSize = NSSize(width: max(width, 1), height: max(height, 1))
        let scale = max(2, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((pointSize.width * scale).rounded(.up)),
            pixelsHigh: Int((pointSize.height * scale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: pointSize)
        }
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }
}
