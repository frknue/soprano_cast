import AppKit
import SopranoCastCore

// The settings window's building blocks in Soprano's settings style (Soprano's
// `SettingsWindowController`): tab header, titled cards, label/control rows separated by
// hairlines, keycap chips and the console buttons. Headings stay lowercase: the display
// face renders small caps.

/// Builds form pieces for one theme.
@MainActor
struct SettingsChrome {
    /// A form row's minimum height.
    static let rowHeight: CGFloat = 30
    /// Inset of a card's content from its edges.
    static let cardInset: CGFloat = 14

    let theme: AppTheme
    var colors: ThemeColors { theme.colors }

    /// The tab title (display 22) over a wrapping body-11 subtitle.
    func tabHeader(title: String, subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.setRetroText(title, color: colors.textPrimary, size: 22)
        stack.addArrangedSubview(titleLabel)
        let subtitleLabel = wrappingLabel(subtitle)
        stack.addArrangedSubview(subtitleLabel)
        subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// A titled section: a heading (and optional subtitle) above a flat `bgPanel` card.
    /// Returns the whole section and the card's content stack.
    func sectionCard(title: String, subtitle: String? = nil) -> (section: NSStackView, body: NSStackView) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        let heading = RetroHeadingView(title: title, theme: theme)
        section.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = wrappingLabel(subtitle)
            section.addArrangedSubview(subtitleLabel)
            section.setCustomSpacing(4, after: heading)
            subtitleLabel.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }

        let card = LayerView(color: colors.bgPanel)
        card.layer?.borderWidth = Retro.hairline
        card.layer?.borderColor = colors.borderStrong.cgColor
        section.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 4
        body.edgeInsets = NSEdgeInsets(top: 8, left: Self.cardInset, bottom: 8, right: Self.cardInset)
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            body.topAnchor.constraint(equalTo: card.topAnchor),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return (section, body)
    }

    /// A label on the left (display 11) and the control pinned to the trailing edge.
    func row(label: String, control: NSView, toolTip: String? = nil) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let labelField = NSTextField(labelWithString: label)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.setRetroText(label, color: colors.textPrimary)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addSubview(labelField)
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(control)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.rowHeight),
            labelField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: 16),
            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 3),
            row.bottomAnchor.constraint(greaterThanOrEqualTo: control.bottomAnchor, constant: 3),
        ])
        let hug = row.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        hug.priority = .defaultLow
        hug.isActive = true
        row.toolTip = toolTip
        return row
    }

    /// Adds views to a card body, full width, separated by inset hairlines.
    func addRows(_ rows: [NSView], to body: NSStackView) {
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let rule = hairline()
                body.addArrangedSubview(rule)
                rule.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -2 * Self.cardInset).isActive = true
            }
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -2 * Self.cardInset).isActive = true
        }
    }

    func hairline() -> NSView {
        RetroRuleView(axis: .horizontal, style: .single, color: colors.borderSubtle)
    }

    func checkbox(isOn: Bool, accessibilityLabel: String, target: AnyObject, action: Selector) -> NSButton {
        let box = NSButton(checkboxWithTitle: "", target: target, action: action)
        box.state = isOn ? .on : .off
        box.contentTintColor = colors.accent
        box.setAccessibilityLabel(accessibilityLabel)
        return box
    }

    /// A pop-up of `titles` with `selected` chosen (nil leaves the first).
    func popup(titles: [String], selected: Int?, width: CGFloat = 220, target: AnyObject, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        if let selected, titles.indices.contains(selected) {
            popup.selectItem(at: selected)
        }
        popup.font = RetroFont.body(12)
        popup.target = target
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        return popup
    }

    /// A bordered body-12 field on `bgRaised` (Soprano's settings field).
    func textField(_ value: String, placeholder: String, width: CGFloat? = nil) -> NSTextField {
        let field = NSTextField(string: value)
        field.isBordered = true
        field.focusRingType = .none
        field.drawsBackground = true
        field.wantsLayer = true
        field.layer?.borderWidth = Retro.hairline
        field.layer?.borderColor = colors.borderStrong.cgColor
        field.backgroundColor = colors.bgRaised
        field.textColor = colors.textPrimary
        field.font = RetroFont.body(12)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: RetroFont.body(12), .foregroundColor: colors.textMuted]
        )
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return field
    }

    func button(_ title: String, kind: RetroButton.Kind = .standard, target: AnyObject, action: Selector) -> RetroButton {
        RetroButton(title: title, theme: theme, kind: kind, target: target, action: action)
    }

    func iconButton(symbol: String, label: String, target: AnyObject, action: Selector) -> RetroIconButton {
        let button = RetroIconButton(symbolName: symbol, accessibilityLabel: label, pointSize: 11, size: 22, target: target, action: action)
        button.setTints(normal: colors.textMuted, hover: colors.accent)
        return button
    }

    /// A horizontal row of views, vertically centered.
    func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    /// Running text in body 11 (muted unless `color` says otherwise), wrapping.
    func wrappingLabel(_ text: String, color: NSColor? = nil, size: CGFloat = 11) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = RetroFont.body(size)
        label.textColor = color ?? colors.textMuted
        label.maximumNumberOfLines = 0
        label.isSelectable = false
        return label
    }

    /// One line of body text, truncating.
    func lineLabel(_ text: String, color: NSColor? = nil, size: CGFloat = 12) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = RetroFont.body(size)
        label.textColor = color ?? colors.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// A settings.json problem: tinted yellow (warning) or `danger` (error), "Line N: …".
    func issueRow(_ issue: ConfigIssue) -> NSView {
        let tint = issue.severity == .error ? colors.danger : colors.yellow
        let row = LayerView(color: tint.withAlphaComponent(0.12))
        row.layer?.borderWidth = Retro.hairline
        row.layer?.borderColor = tint.withAlphaComponent(0.45).cgColor
        let location = issue.line.map { "Line \($0): " } ?? ""
        let label = wrappingLabel(location + issue.message, color: colors.textPrimary)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -7),
        ])
        return row
    }
}

// MARK: - Views

/// A flipped view filled with one color through its layer (offscreen renders include it).
@MainActor
class LayerView: NSView {
    var color: NSColor {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    init(color: NSColor = .clear) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
}

/// A hotkey as Soprano keycap chips ("⌘" "1"), or a muted "record hotkey" when there is
/// none; clicking it records. Accent edges on hover.
@MainActor
final class HotkeyButton: NSButton {
    static let capHeight: CGFloat = 20
    static let capGap: CGFloat = 4

    /// Drawn when there is no hotkey: "record hotkey", or "record" where space is short (the
    /// Extensions table).
    var placeholder = "record hotkey" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Whether the placeholder shows without hovering (the table shows it on the selected
    /// row only, like Raycast's).
    var showsPlaceholder = true {
        didSet { needsDisplay = true }
    }

    var keycaps: [String] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
            setAccessibilityValue(keycaps.joined())
        }
    }
    private var theme: AppTheme
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var hoverArea: NSTrackingArea?

    init(keycaps: [String], theme: AppTheme, target: AnyObject?, action: Selector?) {
        self.keycaps = keycaps
        self.theme = theme
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel("Hotkey")
        setAccessibilityValue(keycaps.joined())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(contentWidth()), height: Self.capHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = theme.colors
        if keycaps.isEmpty {
            guard showsPlaceholder || isHovered else { return }
            let text = RetroText.display(placeholder, color: isHovered ? colors.accent : colors.textMuted)
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.maxX - ceil(size.width), y: floor((bounds.height - size.height) / 2)))
            return
        }
        var x = bounds.maxX - ceil(contentWidth())
        for cap in keycaps {
            let text = RetroText.display(cap, color: colors.textPrimary, tracking: 0)
            let size = text.size()
            let width = Self.capWidth(for: size.width)
            let rect = NSRect(x: x, y: floor((bounds.height - Self.capHeight) / 2), width: width, height: Self.capHeight)
            colors.bgRaised.setFill()
            rect.fill()
            (isHovered ? colors.accent : colors.borderStrong).setStroke()
            let frame = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            frame.lineWidth = Retro.hairline
            frame.stroke()
            text.draw(at: NSPoint(x: rect.minX + floor((width - size.width) / 2), y: rect.minY + floor((Self.capHeight - size.height) / 2)))
            x += width + Self.capGap
        }
    }

    func apply(theme: AppTheme) {
        self.theme = theme
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func contentWidth() -> CGFloat {
        guard !keycaps.isEmpty else {
            return RetroText.display(placeholder, color: .white).size().width
        }
        let widths = keycaps.map { Self.capWidth(for: RetroText.display($0, color: .white, tracking: 0).size().width) }
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * Self.capGap
    }

    private static func capWidth(for textWidth: CGFloat) -> CGFloat {
        max(capHeight, ceil(textWidth) + 12)
    }
}

/// A console key for destructive actions: `RetroButton`'s frame with `danger` ink and edge.
@MainActor
final class DangerButton: NSButton {
    private var theme: AppTheme
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var hoverArea: NSTrackingArea?

    init(title: String, theme: AppTheme, target: AnyObject?, action: Selector?) {
        self.theme = theme
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        let width = ceil(RetroText.display(title, color: .white).size().width)
        return NSSize(width: width + 2 * RetroButton.horizontalPadding, height: Retro.controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = theme.colors
        let isPressed = isHighlighted
        (isPressed ? colors.danger : (isHovered ? colors.danger.withAlphaComponent(0.14) : colors.bgRaised)).setFill()
        bounds.fill()
        colors.danger.setStroke()
        let frame = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        frame.lineWidth = Retro.hairline
        frame.stroke()
        let text = RetroText.display(title, color: isPressed ? colors.bgPanel : colors.danger)
        let size = text.size()
        text.draw(at: NSPoint(x: floor((bounds.width - size.width) / 2), y: floor((bounds.height - size.height) / 2)))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}

/// A settings tab key (Soprano's): the active tab is a lit accent block with panel ink.
@MainActor
final class SettingsTabButton: NSButton {
    private static let inset: CGFloat = 12
    private static let symbolSlot: CGFloat = 16

    let tab: SettingsTab
    var isActive = false {
        didSet { needsDisplay = true }
    }
    private var theme: AppTheme
    private let symbol: NSImage?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var hoverArea: NSTrackingArea?

    init(tab: SettingsTab, theme: AppTheme, target: AnyObject?, action: Selector) {
        self.tab = tab
        self.theme = theme
        symbol = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
        super.init(frame: .zero)
        title = tab.title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func apply(theme: AppTheme) {
        self.theme = theme
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = theme.colors
        let fill: NSColor = isActive ? colors.accent : (isHovered ? colors.bgOverlay : .clear)
        let ink = isActive ? colors.bgPanel : colors.textMuted
        fill.setFill()
        bounds.fill()

        var x = Self.inset
        if let symbol {
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
            let tinted = symbol.withSymbolConfiguration(configuration) ?? symbol
            let size = tinted.size
            tinted.draw(
                in: NSRect(
                    x: x + floor((Self.symbolSlot - size.width) / 2),
                    y: floor((bounds.height - size.height) / 2),
                    width: size.width,
                    height: size.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            x += Self.symbolSlot + 10
        }
        let label = RetroText.display(title, color: ink, tracking: 0)
        let height = ceil(label.size().height)
        label.draw(in: NSRect(x: x, y: floor((bounds.height - height) / 2), width: max(0, bounds.width - x - Self.inset), height: height))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}

/// A vertical scroll of a reading column (≤ `maxWidth`), Soprano's settings content.
@MainActor
final class SettingsScrollColumn: NSView {
    let column = NSStackView()
    private let scrollView = NSScrollView()

    init(maxWidth: CGFloat = 660) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 22
        column.edgeInsets = NSEdgeInsets(top: 24, left: 0, bottom: 28, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)

        let fill = column.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -48)
        // Just below `.windowSizeStayPut` (Soprano's): the column fills the width it gets
        // but never resizes the window to its own fitting width.
        fill.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 1)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: document.topAnchor),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            column.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            fill,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Replaces the column's content; every view spans the column.
    func setContent(_ views: [NSView]) {
        let origin = scrollView.contentView.bounds.origin
        for view in column.arrangedSubviews {
            column.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        layoutSubtreeIfNeeded()
        // Keep the reader's place across rebuilds after an edit.
        let clip = scrollView.contentView
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }
}

/// A plain flipped container.
@MainActor
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
