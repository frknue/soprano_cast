import AppKit
import SopranoCastCore

/// The borderless, non-activating panel the launcher lives in. It becomes key so text
/// input reaches its fields without activating Soprano Cast (the app behind keeps its
/// focus, like Raycast), floats over every app and Space (fullscreen ones too) and stays
/// out of the window cycle.
final class LauncherPanel: NSPanel {
    static let size = CGSize(width: 750, height: 474)

    /// The panel lost key status.
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// A menu-bar app has no Edit menu, so the standard editing shortcuts would never reach
    /// the fields; they go to the first responder directly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let action: Selector? = switch (flags, key) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

// MARK: - Content

/// The panel's root view: search bar, result list (or script output), footer, and the
/// overlay cards on top. Top-left origin.
final class LauncherContentView: LauncherFlippedView {
    static let searchBarHeight: CGFloat = 56
    static let footerHeight: CGFloat = 40
    /// Space between an overlay card and the edges of the list area.
    static let cardMargin: CGFloat = 8

    let searchBar = SearchBarView()
    let list = ResultListView()
    let output = OutputView()
    let footer = FooterView()
    let actionPanel = ActionPanelView()
    let recorder = RecorderCardView()
    let aliasEditor = AliasEditorCardView()
    let confirmation = ConfirmationCardView()

    init() {
        super.init(frame: CGRect(origin: .zero, size: LauncherPanel.size))
        for view: NSView in [list, output, searchBar, footer, actionPanel, recorder, aliasEditor, confirmation] {
            addSubview(view)
        }
        output.isHidden = true
        for card: NSView in [actionPanel, recorder, aliasEditor, confirmation] {
            card.isHidden = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Soprano Cast")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The area between the search bar and the footer.
    var listFrame: CGRect {
        CGRect(
            x: 0,
            y: Self.searchBarHeight,
            width: bounds.width,
            height: bounds.height - Self.searchBarHeight - Self.footerHeight
        )
    }

    /// Draws `model`; existing row views and fields are reconfigured in place.
    func apply(_ model: LauncherViewModel) {
        let theme = model.theme
        let colors = theme.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance = theme.appearance.nsAppearance
        setFrameSize(LauncherPanel.size)
        // Folio `.launcher`: raised, one borderSubtle hairline, radius 12, clipped. The
        // window (or the snapshot) adds the e3 shadow outside.
        layer?.backgroundColor = colors.raised.cgColor
        layer?.borderColor = colors.borderSubtle.cgColor
        layer?.borderWidth = Chrome.hairline
        layer?.cornerRadius = Chrome.Radius.panel
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        searchBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.searchBarHeight)
        searchBar.configure(
            query: model.query,
            placeholder: model.placeholder,
            arguments: model.arguments,
            focus: model.focus,
            theme: theme
        )

        footer.frame = CGRect(x: 0, y: bounds.height - Self.footerHeight, width: bounds.width, height: Self.footerHeight)
        footer.configure(model.footer, theme: theme)

        let listFrame = self.listFrame
        list.frame = listFrame
        list.apply(
            sections: model.sections,
            selectedIndex: model.selectedIndex,
            isFocused: model.focus.isInRootSearch,
            emptyText: model.emptyText,
            theme: theme
        )
        output.frame = listFrame
        applyOverlay(model, theme: theme, listFrame: listFrame)
        CATransaction.commit()
        list.scrollSelectionIntoView()
    }

    private func applyOverlay(_ model: LauncherViewModel, theme: AppTheme, listFrame: CGRect) {
        let overlayFocused = model.focus == .overlay
        var showsOutput = false
        var visibleCard: NSView?
        switch model.overlay {
        case .none:
            break
        case let .actionPanel(title, query, rows, selectedIndex):
            actionPanel.configure(
                title: title, query: query, rows: rows, selectedIndex: selectedIndex,
                focused: overlayFocused, theme: theme
            )
            let maxHeight = listFrame.height - Self.cardMargin * 2
            let height = actionPanel.preferredHeight(maxHeight: maxHeight)
            actionPanel.frame = CGRect(
                x: bounds.width - ActionPanelView.width - Self.cardMargin,
                y: listFrame.maxY - Self.cardMargin - height,
                width: ActionPanelView.width,
                height: height
            )
            actionPanel.layoutContents()
            actionPanel.scrollSelectionIntoView()
            visibleCard = actionPanel
        case let .recorder(itemTitle, keys, conflict, countdown, hints):
            recorder.configure(itemTitle: itemTitle, keys: keys, conflict: conflict, countdown: countdown, hints: hints, theme: theme)
            recorder.frame = centered(RecorderCardView.size(), in: listFrame)
            recorder.layoutContents()
            visibleCard = recorder
        case let .aliasEditor(itemTitle, text, error):
            aliasEditor.configure(itemTitle: itemTitle, text: text, error: error, focused: overlayFocused, theme: theme)
            aliasEditor.frame = centered(AliasEditorCardView.size(), in: listFrame)
            aliasEditor.layoutContents()
            visibleCard = aliasEditor
        case let .output(title, text, isError):
            output.configure(title: title, text: text, isError: isError, theme: theme)
            output.layoutContents()
            showsOutput = true
        case let .confirmation(title, message, confirmTitle):
            confirmation.configure(title: title, message: message, confirmTitle: confirmTitle, theme: theme)
            confirmation.frame = centered(confirmation.preferredSize(), in: listFrame)
            confirmation.layoutContents()
            visibleCard = confirmation
        }
        for card: NSView in [actionPanel, recorder, aliasEditor, confirmation] {
            card.isHidden = card !== visibleCard
        }
        list.isHidden = showsOutput
        output.isHidden = !showsOutput
    }

    private func centered(_ size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.midX - size.width / 2).rounded(),
            y: (rect.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// The overlay's text field, or the output text view, for `focus`.
    func responder(for focus: LauncherFocus, overlay: OverlayViewModel) -> NSView? {
        switch focus {
        case .query:
            return searchBar.queryField
        case let .argument(index):
            return searchBar.argumentBoxes.indices.contains(index) ? searchBar.argumentBoxes[index].control : nil
        case .overlay:
            switch overlay {
            case .actionPanel: return actionPanel.filterField
            case .aliasEditor: return aliasEditor.field
            default: return nil
            }
        case .none:
            if case .output = overlay {
                return output.textView
            }
            return nil
        }
    }
}

// MARK: - Shared primitives

/// A layer-backed view with a top-left origin; every launcher view lays out in it.
class LauncherFlippedView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// Renders this view's layer tree into `context` with its bottom-left corner at
    /// `origin` (`context` uses a bottom-left origin), under `shadow` (the window's e2/e3
    /// elevation). Works for a window that was never on screen: `cacheDisplay` makes
    /// AppKit build and draw every view's layer, then Core Animation renders the tree
    /// (fills, borders, text, icons, keycaps).
    func renderLayerTree(in context: CGContext, at origin: CGPoint, shadow: ThemeShadow) {
        layoutSubtreeIfNeeded()
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
        }
        guard let layer else { return }
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -shadow.offsetY),
            blur: shadow.blur,
            color: shadow.color.withAlphaComponent(CGFloat(shadow.opacity)).cgColor
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: origin.x, y: origin.y)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        // Core Graphics draws shadows in device space, ignoring the flip above: a shadow
        // set to cast down in the flipped tree would render upward. Mirror the offsets for
        // the render and put them back after.
        let shadowed = layer.isGeometryFlipped ? Self.shadowedSublayers(of: layer) : []
        let offsets = shadowed.map(\.shadowOffset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in shadowed {
            sublayer.shadowOffset.height = -sublayer.shadowOffset.height
        }
        layer.render(in: context)
        for (sublayer, offset) in zip(shadowed, offsets) {
            sublayer.shadowOffset = offset
        }
        CATransaction.commit()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Every visible layer under `layer` that casts a shadow.
    private static func shadowedSublayers(of layer: CALayer) -> [CALayer] {
        (layer.sublayers ?? []).flatMap { sublayer -> [CALayer] in
            guard !sublayer.isHidden else { return [] }
            let own = sublayer.shadowOpacity > 0 && sublayer.shadowOffset.height != 0 ? [sublayer] : []
            return own + shadowedSublayers(of: sublayer)
        }
    }
}

/// Text, field and image helpers shared by the launcher views.
@MainActor
enum LauncherText {
    /// A single-line, non-editable label laid out by frame.
    static func label() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = true
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        return label
    }

    /// A borderless single-line input field; `secure` hides what is typed.
    static func inputField(secure: Bool = false) -> NSTextField {
        let field = secure ? NSSecureTextField() : NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        return field
    }

    /// Puts the model's text into `field` only when it differs, so typing keeps its caret
    /// and selection; a replaced text (history recall) leaves the caret at its end.
    static func sync(_ field: NSTextField, to text: String) {
        guard field.stringValue != text else { return }
        field.stringValue = text
        guard let editor = field.currentEditor() else { return }
        if let textView = editor as? NSTextView, textView.string != text {
            textView.string = text
        }
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    /// The caret at the end of the text instead of AppKit's select-all on focus.
    static func moveCaretToEnd(_ field: NSTextField, caret: NSColor) {
        guard let editor = field.currentEditor() else { return }
        editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        (editor as? NSTextView)?.insertionPointColor = caret
    }

    /// Field-editor commands the launcher handles itself (through `onKeyEvent`) or ignores:
    /// a text field must never move focus on Tab or end editing on Return or Escape.
    static func swallows(_ command: Selector) -> Bool {
        command == #selector(NSResponder.insertTab(_:))
            || command == #selector(NSResponder.insertBacktab(_:))
            || command == #selector(NSResponder.insertNewline(_:))
            || command == #selector(NSResponder.insertLineBreak(_:))
            || command == #selector(NSResponder.cancelOperation(_:))
    }

    /// A title with the search hits in `matchFont` and `matchColor` (Folio: Semibold ink,
    /// `matchOnSelection` on the selected row only).
    static func title(
        _ text: String,
        highlights: [NSRange],
        font: NSFont,
        color: NSColor,
        matchFont: NSFont,
        matchColor: NSColor
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: plain(text, font: font, color: color))
        let length = string.length
        for range in highlights where range.location != NSNotFound && range.location < length {
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            string.addAttributes([.foregroundColor: matchColor, .font: matchFont], range: clamped)
        }
        return string
    }

    static func plain(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .natural,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    /// The width a label needs to show `text` untruncated, including the text cell's
    /// 2 pt padding on each side.
    static func width(of text: NSAttributedString) -> CGFloat {
        text.length == 0 ? 0 : ceil(text.size().width) + 4
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// A one-line label frame spanning `minX…maxX`, vertically centered on `centerY`.
    static func lineFrame(minX: CGFloat, maxX: CGFloat, centerY: CGFloat, font: NSFont) -> CGRect {
        let height = lineHeight(font) + 1
        return CGRect(x: minX, y: (centerY - height / 2).rounded(), width: max(0, maxX - minX), height: height)
    }

    /// `image` rasterized for a `side`-point square at `scale` (layers render CGImages in
    /// snapshots; NSImage contents would not).
    static func cgImage(_ image: NSImage, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard side > 0 else { return nil }
        var rect = CGRect(x: 0, y: 0, width: side * scale, height: side * scale)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Launcher keycap sizes (Folio `.kbd`, `.kbd-sm`, `.kbd-lg`).
enum LauncherKeycapStyle {
    /// 18 pt, radius 4, SF 11 Medium: rows, footer, Action Panel.
    case standard
    /// 16 pt: hint rows.
    case small
    /// 36 pt, radius 6, SF 20 Medium: the recorder's keys.
    case large

    var height: CGFloat {
        switch self {
        case .standard: Chrome.keycapHeight
        case .small: Chrome.keycapHeightSmall
        case .large: 36
        }
    }

    var padding: CGFloat {
        switch self {
        case .standard: 5
        case .small: 4
        case .large: 10
        }
    }

    var radius: CGFloat { self == .large ? Chrome.Radius.control : Chrome.Radius.cap }
    var font: NSFont { self == .large ? ChromeFont.sans(size: 20, weight: .medium) : ChromeFont.keycap }
}

/// One K1 cap, drawn like Chrome's `ChromeKeycapView` (`keycapFill`, `keycapEdge`) but
/// laid out by frame like every launcher view.
final class KeycapView: LauncherFlippedView {
    private var legend = ""
    private var style = LauncherKeycapStyle.standard
    private var fill = NSColor.clear
    private var edge = NSColor.clear
    private var ink = NSColor.clear
    private(set) var preferredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `muted` draws the legend in `textMuted` (hint rows).
    func configure(_ legend: String, style: LauncherKeycapStyle, muted: Bool, colors: ThemeColors) {
        self.legend = legend
        self.style = style
        fill = colors.keycapFill
        edge = colors.keycapEdge
        ink = muted ? colors.textMuted : colors.textPrimary
        preferredWidth = ChromeKeycapView.capWidth(legend, font: style.font, height: style.height, padding: style.padding)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        ChromeKeycapView.drawCap(legend, in: bounds, fill: fill, edge: edge, text: ink, font: style.font, radius: style.radius)
    }
}

/// K1 caps left to right with a 3 pt gap ("⌃A" then "P"); cap views are reused.
final class KeycapRowView: LauncherFlippedView {
    static let gap: CGFloat = 3

    private var caps: [KeycapView] = []
    private var capHeight: CGFloat = 0
    private(set) var preferredWidth: CGFloat = 0
    private(set) var keys: [String] = []

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(keys: [String], style: LauncherKeycapStyle = .standard, muted: Bool = false, colors: ThemeColors) {
        self.keys = keys
        capHeight = style.height
        while caps.count > keys.count {
            caps.removeLast().removeFromSuperview()
        }
        while caps.count < keys.count {
            let cap = KeycapView()
            addSubview(cap)
            caps.append(cap)
        }
        for (cap, key) in zip(caps, keys) {
            cap.configure(key, style: style, muted: muted, colors: colors)
        }
        let widths = caps.map(\.preferredWidth).reduce(0, +)
        preferredWidth = caps.isEmpty ? 0 : widths + Self.gap * CGFloat(caps.count - 1)
        layoutCaps()
    }

    /// Cap frames from the left edge, vertically centered.
    func layoutCaps() {
        var x: CGFloat = 0
        let y = ((bounds.height - capHeight) / 2).rounded()
        for cap in caps {
            cap.frame = CGRect(x: x, y: y, width: cap.preferredWidth, height: capHeight)
            x += cap.preferredWidth + Self.gap
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutCaps()
    }
}

/// The alias badge: SF 11 muted on `raised` in a radius-4 chip with a `borderSubtle` edge.
final class BadgeChipView: LauncherFlippedView {
    static let height: CGFloat = Chrome.chipHeight
    static let horizontalPadding: CGFloat = 6

    private var text = NSAttributedString()
    private(set) var preferredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String, colors: ThemeColors) {
        self.text = ChromeText.attributed(text, font: ChromeFont.meta, color: colors.textMuted, lineBreakMode: .byClipping)
        preferredWidth = ceil(self.text.size().width) + Self.horizontalPadding * 2
        layer?.backgroundColor = colors.raised.cgColor
        layer?.borderColor = colors.borderSubtle.cgColor
        layer?.borderWidth = Chrome.hairline
        layer?.cornerRadius = Chrome.Radius.cap
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: Self.horizontalPadding, y: ((bounds.height - size.height) / 2).rounded()))
    }
}

/// A scrollable list's document view that reports which of its `hoverTargets` the
/// pointer is over (tracking areas work while Soprano Cast is not the active app).
class HoverContainerView: LauncherFlippedView {
    var onHover: ((Int?) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var reportedHover: Int?

    /// The views hover indexes refer to, in order.
    var hoverTargets: [NSView] { [] }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        report(nil)
    }

    /// Forgets the reported hover (the rows under the pointer changed).
    func resetHover() {
        reportedHover = nil
    }

    private func reportHover(at point: NSPoint) {
        report(hoverTargets.firstIndex { !$0.isHidden && $0.frame.contains(point) })
    }

    private func report(_ index: Int?) {
        guard index != reportedHover else { return }
        reportedHover = index
        onHover?(index)
    }
}
