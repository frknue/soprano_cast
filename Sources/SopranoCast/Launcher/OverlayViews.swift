import AppKit
import SopranoCastCore

// What sits on top of Root Search: the ⌘K Action Panel, the hotkey recorder, the alias
// editor and the confirmation (cards), and script output (in place of the list).

/// A card (Folio `.menu` / `.dialog`): `raised`, a `borderSubtle` hairline, radius 10 and
/// the e2 shadow.
class LauncherCardView: LauncherFlippedView {
    func applyCardStyle(_ colors: ThemeColors) {
        guard let layer else { return }
        layer.backgroundColor = colors.raised.cgColor
        layer.cornerRadius = Chrome.Radius.popover
        layer.cornerCurve = .continuous
        colors.shadowE2.apply(to: layer)
        layer.borderColor = colors.borderSubtle.cgColor
        layer.borderWidth = Chrome.hairline
    }
}

// MARK: - Action Panel

/// The ⌘K Action Panel (and Configure Command): a 360-wide card with the item title as a
/// meta heading, 30 pt action rows (K1 caps right, destructive ones in `danger`, the
/// selected one a pill with the pencil tick), and the filter field at the bottom.
final class ActionPanelView: LauncherCardView, NSTextFieldDelegate {
    static let width: CGFloat = 360
    /// The card's inner padding (Folio `.menu`).
    static let padding: CGFloat = 5
    static let headingHeight: CGFloat = 24
    static let rowHeight: CGFloat = 30
    static let filterHeight: CGFloat = 36
    static let horizontalInset: CGFloat = 13
    static let placeholder = "Search for actions…"
    static let emptyText = "No results"

    let filterField = LauncherText.inputField()
    /// The filter text changed.
    var onTextChange: ((String) -> Void)?
    /// An action row was clicked (index into the filtered rows).
    var onActionClick: ((Int) -> Void)?

    var rowViews: [ActionRowView] { document.rows }

    private let headingLabel = LauncherText.label()
    private let emptyLabel = LauncherText.label()
    private let scrollView = NSScrollView()
    private let document = ActionListDocumentView()
    private let filterRule = LauncherFlippedView()
    private var rowCount = 0
    private var selectedIndex: Int?
    private var hoveredIndex: Int?

    init() {
        super.init(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = document
        document.onHover = { [weak self] index in self?.setHovered(index) }
        filterField.font = ChromeFont.row
        filterField.delegate = self
        filterField.setAccessibilityLabel("Search for actions")
        emptyLabel.alignment = .center
        for view: NSView in [headingLabel, scrollView, emptyLabel, filterRule, filterField] {
            addSubview(view)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Actions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        title: String,
        query: String,
        rows: [ActionRowViewModel],
        selectedIndex: Int?,
        focused: Bool,
        theme: AppTheme
    ) {
        let colors = theme.colors
        applyCardStyle(colors)
        if rows.count != rowCount {
            hoveredIndex = nil
            document.resetHover()
        }
        rowCount = rows.count
        self.selectedIndex = selectedIndex
        headingLabel.attributedStringValue = LauncherText.plain(title, font: ChromeFont.meta, color: colors.textMuted)
        emptyLabel.attributedStringValue = LauncherText.plain(
            Self.emptyText, font: ChromeFont.meta, color: colors.textMuted, alignment: .center
        )
        filterRule.layer?.backgroundColor = colors.borderSubtle.cgColor
        filterField.textColor = colors.textPrimary
        filterField.placeholderAttributedString = LauncherText.plain(Self.placeholder, font: ChromeFont.row, color: colors.textMuted)
        LauncherText.sync(filterField, to: query)
        if focused {
            ChromeFieldView.styleEditor(of: filterField, colors: colors)
        }

        document.ensureRowCount(rows.count) { [weak self] row in
            row.onClick = { index in self?.onActionClick?(index) }
        }
        let rowWidth = Self.width - Self.padding * 2
        for (index, row) in rows.enumerated() {
            document.rows[index].configure(
                row,
                index: index,
                frame: CGRect(x: Self.padding, y: CGFloat(index) * Self.rowHeight, width: rowWidth, height: Self.rowHeight),
                isSelected: index == selectedIndex,
                isHovered: index == hoveredIndex,
                colors: colors
            )
        }
    }

    /// Heading, every row (at least one row's height for the empty text), the filter.
    func preferredHeight(maxHeight: CGFloat) -> CGFloat {
        let listHeight = CGFloat(max(1, rowCount)) * Self.rowHeight
        return min(maxHeight, Self.padding + Self.headingHeight + listHeight + Self.padding + Chrome.hairline + Self.filterHeight)
    }

    func layoutContents() {
        let width = bounds.width
        headingLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset,
            maxX: width - Self.horizontalInset,
            centerY: Self.padding + Self.headingHeight / 2,
            font: ChromeFont.meta
        )
        let filterTop = bounds.height - Self.filterHeight
        filterRule.frame = CGRect(x: 0, y: filterTop - Chrome.hairline, width: width, height: Chrome.hairline)
        let fieldHeight = LauncherText.lineHeight(ChromeFont.row) + 2
        filterField.frame = CGRect(
            x: Self.horizontalInset,
            y: (filterTop + (Self.filterHeight - fieldHeight) / 2).rounded(),
            width: width - Self.horizontalInset * 2,
            height: fieldHeight
        )
        let listTop = Self.padding + Self.headingHeight
        let listFrame = CGRect(
            x: 0,
            y: listTop,
            width: width,
            height: max(0, filterTop - Chrome.hairline - Self.padding - listTop)
        )
        scrollView.frame = listFrame
        document.setFrameSize(NSSize(width: width, height: max(CGFloat(rowCount) * Self.rowHeight, listFrame.height)))
        emptyLabel.isHidden = rowCount > 0
        emptyLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset,
            maxX: width - Self.horizontalInset,
            centerY: listFrame.midY,
            font: ChromeFont.meta
        )
    }

    /// Keeps the selected action whole in view.
    func scrollSelectionIntoView() {
        guard let selected = selectedIndex, rowViews.indices.contains(selected) else { return }
        let frame = rowViews[selected].frame
        let visible = scrollView.contentView.bounds
        guard frame.minY < visible.minY || frame.maxY > visible.maxY else { return }
        let y = frame.minY < visible.minY ? frame.minY : frame.maxY - visible.height
        let maxY = max(0, document.frame.height - visible.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setHovered(_ index: Int?) {
        guard index != hoveredIndex else { return }
        let previous = hoveredIndex
        hoveredIndex = index
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for changed in [previous, index].compactMap({ $0 }) where rowViews.indices.contains(changed) {
            rowViews[changed].setHovered(changed == index)
        }
        CATransaction.commit()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(filterField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        LauncherText.swallows(commandSelector)
    }
}

/// The Action Panel's document view: owns the action rows and reports hover over them.
final class ActionListDocumentView: HoverContainerView {
    private(set) var rows: [ActionRowView] = []

    override var hoverTargets: [NSView] { rows }

    func ensureRowCount(_ count: Int, prepare: (ActionRowView) -> Void) {
        while rows.count > count {
            rows.removeLast().removeFromSuperview()
        }
        while rows.count < count {
            let row = ActionRowView()
            prepare(row)
            addSubview(row)
            rows.append(row)
        }
    }
}

/// One action (Folio `.menu-row`): SF 13 title (`danger` when destructive) and its K1
/// caps right; the selected one is the selection pill with the pencil tick.
final class ActionRowView: LauncherFlippedView {
    static let leadingInset: CGFloat = 10
    static let trailingInset: CGFloat = 8
    static let keycapHeight: CGFloat = Chrome.keycapHeight

    private(set) var index = 0
    private(set) var title = ""
    private(set) var isSelected = false
    private(set) var isHovered = false
    var onClick: ((Int) -> Void)?

    private let titleLabel = LauncherText.label()
    private let keycaps = KeycapRowView()
    private var colors = AppTheme.folioPaper.colors

    init() {
        super.init(frame: .zero)
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)
        addSubview(keycaps)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        _ row: ActionRowViewModel,
        index: Int,
        frame: CGRect,
        isSelected: Bool,
        isHovered: Bool,
        colors: ThemeColors
    ) {
        self.index = index
        title = row.title
        self.colors = colors
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.frame = frame
        titleLabel.attributedStringValue = LauncherText.plain(
            row.title, font: ChromeFont.row, color: row.isDestructive ? colors.danger : colors.textPrimary
        )
        keycaps.configure(keys: row.keys, colors: colors)
        needsDisplay = true
        layoutContents()
        setAccessibilityLabel(row.title)
        setAccessibilitySelected(isSelected)
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let style: ChromeSelectionPill.Style = isSelected ? .selected : (isHovered ? .hover : .none)
        ChromeSelectionPill.draw(style, in: bounds, colors: colors, inset: 0)
    }

    private func layoutContents() {
        let centerY = bounds.height / 2
        var trailing = bounds.width - Self.trailingInset
        keycaps.isHidden = keycaps.keys.isEmpty
        if !keycaps.keys.isEmpty {
            keycaps.frame = CGRect(
                x: trailing - keycaps.preferredWidth,
                y: (centerY - Self.keycapHeight / 2).rounded(),
                width: keycaps.preferredWidth,
                height: Self.keycapHeight
            )
            keycaps.layoutCaps()
            trailing = keycaps.frame.minX - 10
        }
        titleLabel.frame = LauncherText.lineFrame(
            minX: Self.leadingInset, maxX: trailing, centerY: centerY, font: ChromeFont.row
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) && !isHidden ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(index)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(index)
        return true
    }
}

// MARK: - Hint row

/// Hints (Folio `.hints`): small muted caps, each followed by its word, centered.
final class HintRowView: LauncherFlippedView {
    static let capGap: CGFloat = 5
    static let hintGap: CGFloat = 14

    private var caps: [KeycapRowView] = []
    private var labels: [NSTextField] = []
    private(set) var hints: [RecorderHint] = []

    func configure(_ hints: [RecorderHint], colors: ThemeColors) {
        self.hints = hints
        while caps.count > hints.count {
            caps.removeLast().removeFromSuperview()
            labels.removeLast().removeFromSuperview()
        }
        while caps.count < hints.count {
            let cap = KeycapRowView()
            let label = LauncherText.label()
            addSubview(cap)
            addSubview(label)
            caps.append(cap)
            labels.append(label)
        }
        for (index, hint) in hints.enumerated() {
            caps[index].configure(keys: hint.caps, style: .small, muted: true, colors: colors)
            labels[index].attributedStringValue = LauncherText.plain(hint.label, font: ChromeFont.meta, color: colors.textMuted)
        }
        setAccessibilityLabel(hints.map { "\($0.caps.joined(separator: " ")) \($0.label)" }.joined(separator: ", "))
    }

    func layoutHints() {
        let widths = zip(caps, labels).map { cap, label in
            cap.preferredWidth + Self.capGap + LauncherText.width(of: label.attributedStringValue)
        }
        let total = widths.reduce(0, +) + Self.hintGap * CGFloat(max(0, widths.count - 1))
        var x = ((bounds.width - total) / 2).rounded()
        let centerY = bounds.height / 2
        for (index, cap) in caps.enumerated() {
            let height = LauncherKeycapStyle.small.height
            cap.frame = CGRect(x: x, y: (centerY - height / 2).rounded(), width: cap.preferredWidth, height: height)
            cap.layoutCaps()
            let labelX = cap.frame.maxX + Self.capGap
            let labelWidth = LauncherText.width(of: labels[index].attributedStringValue)
            labels[index].frame = LauncherText.lineFrame(minX: labelX, maxX: labelX + labelWidth, centerY: centerY, font: ChromeFont.meta)
            x = labelX + labelWidth + Self.hintGap
        }
    }
}

// MARK: - Hotkey recorder

/// The hotkey recorder (Folio `.dialog` with `.kbd-lg` caps): the item title as a New York
/// headline, the keys so far as 36 pt caps (or "Recording…" in italic serif), the
/// conflicting owner in `danger`, a 2 pt `textMuted` countdown bar and the key hints.
final class RecorderCardView: LauncherCardView {
    static let width: CGFloat = 380
    static let padding: CGFloat = 20
    static let titleSlot: CGFloat = 22
    static let lineSlot: CGFloat = 16
    static let keycapHeight: CGFloat = LauncherKeycapStyle.large.height
    static let barHeight: CGFloat = 2
    static let recordingText = "Recording…"

    static func size() -> CGSize {
        CGSize(
            width: width,
            height: padding + titleSlot + 14 + keycapHeight + 10 + lineSlot + 10 + barHeight + 14 + lineSlot + padding
        )
    }

    private let titleLabel = LauncherText.label()
    private let keycaps = KeycapRowView()
    private let recordingLabel = LauncherText.label()
    private let conflictLabel = LauncherText.label()
    private let countdownBar = LauncherFlippedView()
    private let hintRow = HintRowView()
    private var countdown: Double?

    /// The keycaps showing, for tests.
    var shownKeys: [String] { keycaps.keys }
    /// The countdown bar's width (0 while hidden), for tests.
    var countdownWidth: CGFloat { countdownBar.isHidden ? 0 : countdownBar.frame.width }

    init() {
        super.init(frame: .zero)
        for label in [titleLabel, recordingLabel, conflictLabel] {
            label.alignment = .center
        }
        for view: NSView in [titleLabel, keycaps, recordingLabel, conflictLabel, countdownBar, hintRow] {
            addSubview(view)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Record hotkey")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(itemTitle: String, keys: [String], conflict: String?, countdown: Double?, hints: [RecorderHint], theme: AppTheme) {
        let colors = theme.colors
        applyCardStyle(colors)
        self.countdown = countdown
        titleLabel.attributedStringValue = LauncherText.plain(itemTitle, font: ChromeFont.headline, color: colors.textPrimary, alignment: .center)
        keycaps.configure(keys: keys, style: .large, colors: colors)
        recordingLabel.attributedStringValue = LauncherText.plain(
            Self.recordingText, font: ChromeFont.empty, color: colors.textMuted, alignment: .center
        )
        conflictLabel.attributedStringValue = LauncherText.plain(conflict ?? "", font: ChromeFont.label, color: colors.danger, alignment: .center)
        countdownBar.layer?.backgroundColor = colors.textMuted.cgColor
        countdownBar.layer?.cornerRadius = 1
        hintRow.configure(hints, colors: colors)
    }

    func layoutContents() {
        let width = bounds.width
        let minX = Self.padding
        let maxX = width - Self.padding
        var y = Self.padding
        titleLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.titleSlot / 2, font: ChromeFont.headline)
        y += Self.titleSlot + 14

        let hasKeys = !keycaps.keys.isEmpty
        keycaps.isHidden = !hasKeys
        recordingLabel.isHidden = hasKeys
        if hasKeys {
            let keysWidth = min(keycaps.preferredWidth, maxX - minX)
            keycaps.frame = CGRect(x: ((width - keysWidth) / 2).rounded(), y: y, width: keysWidth, height: Self.keycapHeight)
            keycaps.layoutCaps()
        } else {
            recordingLabel.frame = LauncherText.lineFrame(
                minX: minX, maxX: maxX, centerY: y + Self.keycapHeight / 2, font: ChromeFont.empty
            )
        }
        y += Self.keycapHeight + 10

        conflictLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: ChromeFont.label)
        conflictLabel.isHidden = conflictLabel.attributedStringValue.length == 0
        y += Self.lineSlot + 10

        let progress = countdown.map { CGFloat(min(max($0, 0), 1)) } ?? 0
        let barWidth = ((maxX - minX) * progress).rounded()
        // Nothing at 0: a zero-width bar would still show its rounded ends.
        countdownBar.isHidden = barWidth < 1
        countdownBar.frame = CGRect(x: minX, y: y, width: barWidth, height: Self.barHeight)
        y += Self.barHeight + 14

        hintRow.frame = CGRect(x: minX, y: y, width: maxX - minX, height: Self.lineSlot)
        hintRow.layoutHints()
    }
}

// MARK: - Alias editor

/// The alias editor (Folio `.dialog`): the item title as a headline, a `.field` (its edge
/// darkens to `fieldFocusEdge` while focused) and the validation error in `danger`.
final class AliasEditorCardView: LauncherCardView, NSTextFieldDelegate {
    static let width: CGFloat = 380
    static let padding: CGFloat = 20
    static let titleSlot: CGFloat = 22
    static let lineSlot: CGFloat = 16
    static let fieldBoxHeight: CGFloat = Chrome.fieldHeight
    static let placeholder = "alias"

    static func size() -> CGSize {
        CGSize(width: width, height: padding + titleSlot + 12 + fieldBoxHeight + 8 + lineSlot + padding)
    }

    let field = LauncherText.inputField()
    /// The text changed.
    var onTextChange: ((String) -> Void)?

    private let titleLabel = LauncherText.label()
    private let fieldBox = LauncherFlippedView()
    private let errorLabel = LauncherText.label()

    init() {
        super.init(frame: .zero)
        field.font = ChromeFont.row
        field.delegate = self
        field.setAccessibilityLabel("Alias")
        fieldBox.addSubview(field)
        for view: NSView in [titleLabel, fieldBox, errorLabel] {
            addSubview(view)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Alias")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(itemTitle: String, text: String, error: String?, focused: Bool, theme: AppTheme) {
        let colors = theme.colors
        applyCardStyle(colors)
        titleLabel.attributedStringValue = LauncherText.plain(itemTitle, font: ChromeFont.headline, color: colors.textPrimary)
        fieldBox.layer?.backgroundColor = colors.raised.cgColor
        fieldBox.layer?.borderColor = (error != nil ? colors.danger : (focused ? colors.fieldFocusEdge : colors.borderStrong)).cgColor
        fieldBox.layer?.borderWidth = Chrome.hairline
        fieldBox.layer?.cornerRadius = Chrome.Radius.control
        field.textColor = colors.textPrimary
        field.placeholderAttributedString = LauncherText.plain(Self.placeholder, font: ChromeFont.row, color: colors.textMuted)
        LauncherText.sync(field, to: text)
        if focused {
            ChromeFieldView.styleEditor(of: field, colors: colors)
        }
        errorLabel.attributedStringValue = LauncherText.plain(error ?? "", font: ChromeFont.label, color: colors.danger)
        errorLabel.isHidden = error == nil
    }

    func layoutContents() {
        let minX = Self.padding
        let maxX = bounds.width - Self.padding
        var y = Self.padding
        titleLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.titleSlot / 2, font: ChromeFont.headline)
        y += Self.titleSlot + 12
        fieldBox.frame = CGRect(x: minX, y: y, width: maxX - minX, height: Self.fieldBoxHeight)
        let fieldHeight = LauncherText.lineHeight(ChromeFont.row) + 2
        field.frame = CGRect(
            x: 8,
            y: ((Self.fieldBoxHeight - fieldHeight) / 2).rounded(),
            width: max(0, fieldBox.bounds.width - 16),
            height: fieldHeight
        )
        y += Self.fieldBoxHeight + 8
        errorLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: ChromeFont.label)
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        LauncherText.swallows(commandSelector)
    }
}

// MARK: - Confirmation

/// "Are you sure?" (Folio `.dialog`): the title as a headline, the message (SF 13 muted),
/// and the Cancel (`esc`) and confirm (`↵`) buttons. Every confirmation guards a
/// destructive command, so the confirm button is the danger button.
final class ConfirmationCardView: LauncherCardView {
    static let width: CGFloat = 400
    static let padding: CGFloat = 20
    static let titleSlot: CGFloat = 22
    static let buttonGap: CGFloat = 8

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private let titleLabel = LauncherText.label()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = ChromeButton(title: "Cancel", theme: .folioPaper, kind: .standard, keycap: "esc")
    private let confirmButton = ChromeButton(title: "", theme: .folioPaper, kind: .danger, keycap: "↵")
    private var messageHeight: CGFloat = 0

    /// The confirm button's title, for tests.
    var confirmButtonTitle: String { confirmButton.title }

    init() {
        super.init(frame: .zero)
        messageLabel.translatesAutoresizingMaskIntoConstraints = true
        for button in [cancelButton, confirmButton] {
            button.translatesAutoresizingMaskIntoConstraints = true
            button.target = self
        }
        cancelButton.action = #selector(cancelClicked)
        confirmButton.action = #selector(confirmClicked)
        for view: NSView in [titleLabel, messageLabel, cancelButton, confirmButton] {
            addSubview(view)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Confirm")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, message: String, confirmTitle: String, theme: AppTheme) {
        let colors = theme.colors
        applyCardStyle(colors)
        titleLabel.attributedStringValue = LauncherText.plain(title, font: ChromeFont.headline, color: colors.textPrimary)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = 19
        let messageText = NSAttributedString(string: message, attributes: [
            .font: ChromeFont.row, .foregroundColor: colors.textMuted, .paragraphStyle: paragraph,
        ])
        messageLabel.attributedStringValue = messageText
        let textWidth = Self.width - Self.padding * 2
        messageHeight = message.isEmpty ? 0 : ceil(messageText.boundingRect(
            with: CGSize(width: textWidth - 4, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 2
        cancelButton.apply(theme: theme)
        confirmButton.apply(theme: theme)
        confirmButton.title = confirmTitle
    }

    func preferredSize() -> CGSize {
        let messageBlock = messageHeight > 0 ? messageHeight + 8 : 0
        return CGSize(
            width: Self.width,
            height: Self.padding + Self.titleSlot + 8 + messageBlock + 8 + Chrome.controlHeight + Self.padding - 4
        )
    }

    func layoutContents() {
        let minX = Self.padding
        let maxX = bounds.width - Self.padding
        var y = Self.padding
        titleLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.titleSlot / 2, font: ChromeFont.headline)
        y += Self.titleSlot + 8
        messageLabel.isHidden = messageHeight == 0
        messageLabel.frame = CGRect(x: minX, y: y, width: maxX - minX, height: messageHeight)
        if messageHeight > 0 {
            y += messageHeight + 8
        }
        y += 8
        let confirmWidth = confirmButton.intrinsicContentSize.width
        let cancelWidth = cancelButton.intrinsicContentSize.width
        confirmButton.frame = CGRect(x: maxX - confirmWidth, y: y, width: confirmWidth, height: Chrome.controlHeight)
        cancelButton.frame = CGRect(
            x: confirmButton.frame.minX - Self.buttonGap - cancelWidth,
            y: y,
            width: cancelWidth,
            height: Chrome.controlHeight
        )
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func confirmClicked() {
        onConfirm?()
    }
}

// MARK: - Output

/// Script output (fullOutput mode) in place of the list: an SF 13 Medium title row over a
/// selectable SF Mono 12 text view.
final class OutputView: LauncherFlippedView {
    static let titleHeight: CGFloat = 36
    static let horizontalInset: CGFloat = 20
    static let titleFont = ChromeFont.sans(size: 13, weight: .medium)

    let textView: NSTextView
    private let scrollView = NSScrollView()
    private let titleLabel = LauncherText.label()
    private let rule = LauncherFlippedView()

    /// The text showing.
    var text: String { textView.string }

    init() {
        textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        super.init(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = ChromeFont.mono
        textView.textContainerInset = NSSize(width: Self.horizontalInset - 5, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Output")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = textView
        for view: NSView in [titleLabel, rule, scrollView] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, text: String, isError: Bool, theme: AppTheme) {
        let colors = theme.colors
        titleLabel.attributedStringValue = LauncherText.plain(title, font: Self.titleFont, color: isError ? colors.danger : colors.textPrimary)
        rule.layer?.backgroundColor = colors.borderSubtle.cgColor
        textView.textColor = colors.textPrimary
        textView.insertionPointColor = colors.caret
        textView.selectedTextAttributes = [.backgroundColor: colors.textSelection]
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        textView.defaultParagraphStyle = paragraph
        if textView.string != text {
            textView.string = text
            textView.textColor = colors.textPrimary
            textView.font = ChromeFont.mono
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (text as NSString).length))
            textView.scroll(.zero)
        }
    }

    func layoutContents() {
        titleLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset,
            maxX: bounds.width - Self.horizontalInset,
            centerY: Self.titleHeight / 2,
            font: Self.titleFont
        )
        rule.frame = CGRect(x: 0, y: Self.titleHeight, width: bounds.width, height: Chrome.hairline)
        let top = Self.titleHeight + Chrome.hairline
        scrollView.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        let contentWidth = scrollView.contentSize.width
        if textView.frame.width != contentWidth {
            textView.setFrameSize(NSSize(width: contentWidth, height: max(textView.frame.height, scrollView.contentSize.height)))
        }
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
}
