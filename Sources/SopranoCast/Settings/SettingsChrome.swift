import AppKit
import SopranoCastCore

// The settings window's building blocks in Soprano's Folio settings style: the screen
// title, eyebrow sections over raised cards, label/control form rows separated by inset
// hairlines, switches, fields, keycaps and the Chrome buttons. Strings arrive in sentence
// case; eyebrows uppercase them in the view.

/// Builds form pieces for one theme.
@MainActor
struct SettingsChrome {
    /// A form row's minimum height (`.form-row`).
    static let rowHeight: CGFloat = 36
    /// A form row's vertical padding.
    static let rowPadding: CGFloat = 8
    /// Horizontal inset of a card's content; separators start here.
    static let cardInset: CGFloat = 12
    /// The Extensions detail pane's denser rows (`.ext-detail .form-row`).
    static let detailRowHeight: CGFloat = 40
    static let detailRowPadding: CGFloat = 6

    let theme: AppTheme
    var colors: ThemeColors { theme.colors }

    /// The screen title (New York 22) over a wrapping meta subtitle.
    func tabHeader(title: String, subtitle: String, titleFont: NSFont = ChromeFont.screen) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.isSelectable = false
        titleLabel.setChromeText(title, font: titleFont, color: colors.textPrimary, tracking: titleFont.pointSize >= 22 ? -0.2 : 0)
        stack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let subtitleLabel = wrappingLabel(subtitle)
        stack.addArrangedSubview(subtitleLabel)
        subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// A section (`.settings-section`): an eyebrow, an optional note and a raised card.
    /// Returns the whole section and the card's content stack (fill it with `addRows`).
    func sectionCard(title: String, subtitle: String? = nil) -> (section: NSStackView, body: NSStackView) {
        let section = NSStackView()
        section.orientation = .vertical
        // Trailing: the eyebrow and note are 2 pt narrower than the card, so they sit 2 pt in.
        section.alignment = .trailing
        section.spacing = 8

        let heading = ChromeEyebrowView(title: title, theme: theme)
        section.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -2).isActive = true

        if let subtitle, !subtitle.isEmpty {
            let note = wrappingLabel(subtitle)
            section.addArrangedSubview(note)
            section.setCustomSpacing(4, after: heading)
            note.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -2).isActive = true
        }

        let card = LayerView(color: colors.raised)
        card.layer?.borderWidth = Chrome.hairline
        card.layer?.borderColor = colors.borderSubtle.cgColor
        card.layer?.cornerRadius = Chrome.Radius.card
        card.layer?.masksToBounds = true
        section.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 0
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

    /// A form row: the label (SF 13) on the left and the control pinned to the trailing edge.
    func row(
        label: String,
        control: NSView,
        toolTip: String? = nil,
        minHeight: CGFloat = Self.rowHeight,
        padding: CGFloat = Self.rowPadding
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let labelField = NSTextField(labelWithString: label)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.setChromeText(label, font: ChromeFont.row, color: colors.textPrimary)
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addSubview(labelField)
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(control)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            labelField.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.cardInset),
            labelField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Self.cardInset),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: 16),
            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: padding),
            row.bottomAnchor.constraint(greaterThanOrEqualTo: control.bottomAnchor, constant: padding),
        ])
        let hug = row.heightAnchor.constraint(equalToConstant: minHeight)
        hug.priority = .defaultLow
        hug.isActive = true
        row.toolTip = toolTip
        return row
    }

    /// Any view as a card row with the form padding: full width when `fill`, else leading.
    func content(_ view: NSView, fill: Bool = true, padding: CGFloat = Self.rowPadding) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.cardInset),
            fill
                ? view.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Self.cardInset)
                : view.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -Self.cardInset),
            view.topAnchor.constraint(equalTo: row.topAnchor, constant: padding),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: padding),
        ])
        return row
    }

    /// Adds rows to a card body, full width, separated by hairlines inset 12 from the left.
    func addRows(_ rows: [NSView], to body: NSStackView) {
        for (index, row) in rows.enumerated() {
            if index > 0 || !body.arrangedSubviews.isEmpty {
                let rule = CardRuleView(color: colors.borderSubtle)
                body.addArrangedSubview(rule)
                rule.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            }
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }

    /// A boolean form control (`.switch`); `state` reads like a checkbox's.
    func switchControl(isOn: Bool, accessibilityLabel: String, target: AnyObject, action: Selector) -> ChromeSwitch {
        let control = ChromeSwitch(isOn: isOn, theme: theme, target: target, action: action)
        control.setAccessibilityLabel(accessibilityLabel)
        return control
    }

    /// The dense-table checkbox (`.table-row .checkbox`): outline and ink tick.
    func tableCheckbox(isOn: Bool, accessibilityLabel: String, target: AnyObject, action: Selector) -> ChromeCheckbox {
        let box = ChromeCheckbox(isChecked: isOn, theme: theme, style: .quiet, target: target, action: action)
        box.setAccessibilityLabel(accessibilityLabel)
        return box
    }

    /// A native pop-up of `titles` with `selected` chosen (nil leaves the first); it takes
    /// the window's appearance.
    func popup(titles: [String], selected: Int?, width: CGFloat = 220, target: AnyObject?, action: Selector?) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        if let selected, titles.indices.contains(selected) {
            popup.selectItem(at: selected)
        }
        popup.controlSize = .regular
        popup.font = ChromeFont.label
        popup.target = target
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popup.widthAnchor.constraint(equalToConstant: width),
            popup.heightAnchor.constraint(equalToConstant: Chrome.controlHeight),
        ])
        return popup
    }

    /// A `.field`: 26 pt raised surface with an embedded SF 12 text field.
    func textField(_ value: String, placeholder: String, width: CGFloat? = nil) -> SettingsField {
        let field = SettingsField(theme: theme, placeholder: placeholder)
        field.stringValue = value
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return field
    }

    func button(_ title: String, kind: ChromeButton.Kind = .standard, target: AnyObject, action: Selector) -> ChromeButton {
        ChromeButton(title: title, theme: theme, kind: kind, target: target, action: action)
    }

    /// A muted icon key that turns ink on hover.
    func iconButton(symbol: String, label: String, pointSize: CGFloat = 13, size: CGFloat = ChromeIconButton.defaultSize, target: AnyObject, action: Selector) -> ChromeIconButton {
        let button = ChromeIconButton(symbolName: symbol, accessibilityLabel: label, pointSize: pointSize, size: size, target: target, action: action)
        button.apply(theme: theme)
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

    /// Running text, meta 11 muted unless told otherwise, wrapping.
    func wrappingLabel(_ text: String, color: NSColor? = nil, font: NSFont = ChromeFont.meta) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color ?? colors.textMuted
        label.maximumNumberOfLines = 0
        label.isSelectable = false
        return label
    }

    /// One line of text, SF 12 ink unless told otherwise, truncating.
    func lineLabel(_ text: String, color: NSColor? = nil, font: NSFont = ChromeFont.label) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color ?? colors.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// A settings.json problem on its status wash: a yellow dot (warning) or a danger
    /// diamond (error) and "Line N: …" in SF 12.
    func issueRow(_ issue: ConfigIssue) -> NSView {
        let isError = issue.severity == .error
        let row = LayerView(color: isError ? colors.errorWash : colors.needsInputWash)
        row.layer?.cornerRadius = Chrome.Radius.control
        let mark = ChromeStatusMark(
            shape: isError ? .diamond : .dot,
            color: isError ? colors.danger : colors.yellow,
            size: Chrome.statusMark
        )
        mark.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(mark)
        let location = issue.line.map { "Line \($0): " } ?? ""
        let label = wrappingLabel(location + issue.message, color: colors.textPrimary, font: ChromeFont.label)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        let firstLine = ceil(ChromeFont.label.ascender - ChromeFont.label.descender + ChromeFont.label.leading)
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            mark.widthAnchor.constraint(equalToConstant: Chrome.statusMark),
            mark.heightAnchor.constraint(equalToConstant: Chrome.statusMark),
            mark.centerYAnchor.constraint(equalTo: label.topAnchor, constant: firstLine / 2),
            label.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 8),
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

/// The separator between two card rows: one hairline starting `cardInset` in.
@MainActor
final class CardRuleView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Chrome.hairline)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSRect(x: SettingsChrome.cardInset, y: 0, width: max(0, bounds.width - SettingsChrome.cardInset), height: bounds.height).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A text field that reports when it gains and loses the field editor, giving the editor
/// the theme's caret and selection.
@MainActor
final class SettingsTextField: NSTextField {
    var colors: ThemeColors?
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let colors {
            ChromeFieldView.styleEditor(of: self, colors: colors)
        }
        onFocusChange?(true)
        return true
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

/// A `.field` or `.search-field`: a 26 pt `ChromeFieldView` with an optional 13 pt muted
/// symbol and an embedded field whose edge darkens while it is edited.
@MainActor
final class SettingsField: NSView {
    let field = SettingsTextField(string: "")
    private let surface: ChromeFieldView
    private let symbol: NSImageView?
    private let symbolName: String?
    private let placeholder: String

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    var delegate: NSTextFieldDelegate? {
        get { field.delegate }
        set { field.delegate = newValue }
    }

    init(theme: AppTheme, placeholder: String, symbolName: String? = nil) {
        self.placeholder = placeholder
        self.symbolName = symbolName
        surface = ChromeFieldView(theme: theme)
        symbol = symbolName.map { _ in NSImageView() }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.onFocusChange = { [weak self] focused in self?.surface.isFocused = focused }
        for view in ([surface, symbol, field] as [NSView?]).compactMap({ $0 }) {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        var constraints = [
            heightAnchor.constraint(equalToConstant: Chrome.fieldHeight),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if let symbol {
            symbol.setContentHuggingPriority(.required, for: .horizontal)
            constraints += [
                symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
                field.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 6),
            ]
        } else {
            constraints.append(field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8))
        }
        NSLayoutConstraint.activate(constraints)
        apply(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func apply(theme: AppTheme) {
        let colors = theme.colors
        surface.apply(theme: theme)
        ChromeFieldView.styleEmbedded(field, colors: colors)
        field.colors = colors
        field.placeholderAttributedString = ChromeText.attributed(placeholder, font: ChromeFont.label, color: colors.textMuted)
        if let symbol, let symbolName {
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [colors.textMuted]))
            symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }
    }
}

/// A hotkey as K1 keycaps (`⌘1`), or a muted "Record hotkey" when there is none; clicking
/// it records. The edges and the placeholder turn ink on hover.
@MainActor
final class HotkeyButton: NSButton {
    static let capGap: CGFloat = 3

    /// The caps' size: `field` (24, the settings control), `standard` (18) or `small` (16,
    /// the Extensions table).
    var capStyle: ChromeKeycapView.Style = .field {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Drawn when there is no hotkey: "Record hotkey", or "Record" where space is short (the
    /// Extensions table).
    var placeholder = "Record hotkey" {
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
            setAccessibilityValue(keycaps.joined(separator: " "))
        }
    }
    private var theme: AppTheme
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var hoverArea: NSTrackingArea?

    init(keycaps: [String], theme: AppTheme, style: ChromeKeycapView.Style = .field, target: AnyObject?, action: Selector?) {
        self.keycaps = keycaps
        self.theme = theme
        capStyle = style
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityLabel("Hotkey")
        setAccessibilityValue(keycaps.joined(separator: " "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(contentWidth()), height: metrics.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = theme.colors
        if keycaps.isEmpty {
            guard showsPlaceholder || isHovered else { return }
            let text = ChromeText.attributed(placeholder, font: ChromeFont.meta, color: isHovered ? colors.textPrimary : colors.textMuted)
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.maxX - ceil(size.width), y: floor((bounds.height - size.height) / 2)))
            return
        }
        let metrics = metrics
        var x = bounds.maxX - ceil(contentWidth())
        for cap in keycaps {
            let width = capWidth(cap)
            let rect = NSRect(x: x, y: floor((bounds.height - metrics.height) / 2), width: width, height: metrics.height)
            ChromeKeycapView.drawCap(
                cap,
                in: rect,
                fill: colors.keycapFill,
                edge: isHovered ? colors.fieldFocusEdge : colors.keycapEdge,
                text: colors.textPrimary,
                font: metrics.font,
                radius: metrics.radius
            )
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

    /// `ChromeKeycapView`'s metrics for `capStyle`.
    private var metrics: (height: CGFloat, padding: CGFloat, minWidth: CGFloat, radius: CGFloat, font: NSFont) {
        switch capStyle {
        case .standard: (Chrome.keycapHeight, 5, Chrome.keycapHeight, Chrome.Radius.cap, ChromeFont.keycap)
        case .small: (Chrome.keycapHeightSmall, 4, Chrome.keycapHeightSmall, Chrome.Radius.cap, ChromeFont.keycap)
        case .field: (Chrome.controlHeight, 10, 84, Chrome.Radius.control, ChromeFont.sans(size: 12, weight: .medium))
        }
    }

    private func capWidth(_ cap: String) -> CGFloat {
        let metrics = metrics
        return ChromeKeycapView.capWidth(cap, font: metrics.font, height: metrics.minWidth, padding: metrics.padding)
    }

    private func contentWidth() -> CGFloat {
        guard !keycaps.isEmpty else {
            return ChromeText.attributed(placeholder, font: ChromeFont.meta, color: .labelColor).size().width
        }
        let widths = keycaps.map(capWidth)
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * Self.capGap
    }
}

/// A settings nav item (`.nav-item`): 14 pt symbol and SF 12 label, muted; a hover pill
/// under the pointer; the active tab on a raised pill in ink Medium. No accent.
@MainActor
final class SettingsTabButton: NSButton {
    static let height: CGFloat = 30
    private static let inset: CGFloat = 10
    private static let symbolSlot: CGFloat = 16
    private static let symbolGap: CGFloat = 8

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
        let style: ChromeSelectionPill.Style = isActive ? .raisedTab : (isHovered ? .hover : .none)
        ChromeSelectionPill.draw(style, in: bounds, colors: colors, inset: 0)
        let ink = isActive ? colors.textPrimary : colors.textMuted

        var x = Self.inset
        if let symbol {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
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
            x += Self.symbolSlot + Self.symbolGap
        }
        let label = ChromeText.attributed(
            title,
            font: isActive ? ChromeFont.labelStrong : ChromeFont.label,
            color: ink,
            lineBreakMode: .byTruncatingTail
        )
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

    /// `spacing` between sections; `insets` around the column (left and right give the
    /// gutter on each side).
    init(maxWidth: CGFloat = 660, spacing: CGFloat = Chrome.Space.s24, insets: NSEdgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 28, right: 24)) {
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
        column.spacing = spacing
        column.edgeInsets = NSEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)

        let fill = column.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -(insets.left + insets.right))
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
            column.centerXAnchor.constraint(equalTo: document.centerXAnchor, constant: (insets.left - insets.right) / 2),
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
