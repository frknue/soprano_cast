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
        appearance = NSAppearance(named: .darkAqua)
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
        setFrameSize(LauncherPanel.size)
        layer?.backgroundColor = colors.bgBase.withAlphaComponent(0.98).cgColor
        layer?.borderColor = colors.borderStrong.cgColor
        layer?.borderWidth = Retro.hairline
        layer?.cornerRadius = Retro.cornerRadius

        searchBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.searchBarHeight)
        searchBar.configure(
            query: model.query,
            placeholder: model.placeholder,
            arguments: model.arguments,
            focus: model.focus,
            colors: colors
        )

        footer.frame = CGRect(x: 0, y: bounds.height - Self.footerHeight, width: bounds.width, height: Self.footerHeight)
        footer.configure(model.footer, colors: colors)

        let listFrame = self.listFrame
        list.frame = listFrame
        list.apply(sections: model.sections, selectedIndex: model.selectedIndex, emptyText: model.emptyText, theme: theme)
        output.frame = listFrame
        applyOverlay(model, theme: theme, listFrame: listFrame)
        CATransaction.commit()
        list.scrollSelectionIntoView()
    }

    private func applyOverlay(_ model: LauncherViewModel, theme: AppTheme, listFrame: CGRect) {
        let colors = theme.colors
        let overlayFocused = model.focus == .overlay
        var showsOutput = false
        var visibleCard: NSView?
        switch model.overlay {
        case .none:
            break
        case let .actionPanel(title, query, rows, selectedIndex):
            actionPanel.configure(
                title: title, query: query, rows: rows, selectedIndex: selectedIndex,
                focused: overlayFocused, colors: colors
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
        case let .recorder(itemTitle, keys, conflict, countdown, hint):
            recorder.configure(itemTitle: itemTitle, keys: keys, conflict: conflict, countdown: countdown, hint: hint, colors: colors)
            recorder.frame = centered(RecorderCardView.size(), in: listFrame)
            recorder.layoutContents()
            visibleCard = recorder
        case let .aliasEditor(itemTitle, text, error):
            aliasEditor.configure(itemTitle: itemTitle, text: text, error: error, focused: overlayFocused, colors: colors)
            aliasEditor.frame = centered(AliasEditorCardView.size(), in: listFrame)
            aliasEditor.layoutContents()
            visibleCard = aliasEditor
        case let .output(title, text, isError):
            output.configure(title: title, text: text, isError: isError, colors: colors)
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
    /// `origin` (`context` uses a bottom-left origin), with a drop shadow. Works for a
    /// window that was never on screen: `cacheDisplay` makes AppKit build and draw every
    /// view's layer, then Core Animation renders the tree (fills, borders, text, icons,
    /// keycaps).
    func renderLayerTree(in context: CGContext, at origin: CGPoint) {
        layoutSubtreeIfNeeded()
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
        }
        guard let layer else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.55).cgColor)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: origin.x, y: origin.y)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        context.endTransparencyLayer()
        context.restoreGState()
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

    /// A title with the search hits in `highlight`.
    static func title(
        _ text: String,
        highlights: [NSRange],
        font: NSFont,
        color: NSColor,
        highlight: NSColor
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: plain(text, font: font, color: color))
        let length = string.length
        for range in highlights where range.location != NSNotFound && range.location < length {
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            string.addAttribute(.foregroundColor, value: highlight, range: clamped)
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

/// One key of a shortcut: a square-cornered `bgRaised` cap with a `borderStrong` hairline
/// and the key in the display face.
final class KeycapView: LauncherFlippedView {
    static let horizontalPadding: CGFloat = 5

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

    func configure(_ key: String, fontSize: CGFloat, height: CGFloat, colors: ThemeColors) {
        text = RetroText.display(key, color: colors.textPrimary, size: fontSize, tracking: 0, lineBreakMode: .byClipping)
        preferredWidth = max(height, ceil(text.size().width) + Self.horizontalPadding * 2)
        layer?.backgroundColor = colors.bgRaised.cgColor
        layer?.borderColor = colors.borderStrong.cgColor
        layer?.borderWidth = Retro.hairline
        layer?.cornerRadius = Retro.cornerRadius
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((bounds.height - size.height) / 2).rounded()
        ))
    }
}

/// A row of keycaps ("⌘", "K"), left to right; cap views are reused.
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

    func configure(keys: [String], fontSize: CGFloat, height: CGFloat, colors: ThemeColors) {
        self.keys = keys
        capHeight = height
        while caps.count > keys.count {
            caps.removeLast().removeFromSuperview()
        }
        while caps.count < keys.count {
            let cap = KeycapView()
            addSubview(cap)
            caps.append(cap)
        }
        for (cap, key) in zip(caps, keys) {
            cap.configure(key, fontSize: fontSize, height: height, colors: colors)
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

/// A badge: display-face text in `textMuted` on `bgRaised` with a `borderSubtle` hairline.
final class BadgeChipView: LauncherFlippedView {
    static let height: CGFloat = 18
    static let horizontalPadding: CGFloat = 5

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
        self.text = RetroText.display(text, color: colors.textMuted, lineBreakMode: .byClipping)
        preferredWidth = ceil(self.text.size().width) + Self.horizontalPadding * 2
        layer?.backgroundColor = colors.bgRaised.cgColor
        layer?.borderColor = colors.borderSubtle.cgColor
        layer?.borderWidth = Retro.hairline
        layer?.cornerRadius = Retro.cornerRadius
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
