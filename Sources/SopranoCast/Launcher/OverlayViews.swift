import AppKit
import SopranoCastCore

// What sits on top of Root Search: the ⌘K Action Panel, the hotkey recorder, the alias
// editor and the confirmation (cards), and script output (in place of the list).

/// A card: `bgPanel`, a `borderStrong` hairline, square corners and a drop shadow.
class LauncherCardView: LauncherFlippedView {
    func applyCardStyle(_ colors: ThemeColors) {
        guard let layer else { return }
        layer.backgroundColor = colors.bgPanel.cgColor
        layer.borderColor = colors.borderStrong.cgColor
        layer.borderWidth = Retro.hairline
        layer.cornerRadius = Retro.cornerRadius
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -4)
    }
}

// MARK: - Action Panel

/// The ⌘K Action Panel (and Configure Command): a 360-wide card with the item title as
/// heading, 32 pt action rows (keycaps right, destructive ones in `danger`), and the
/// filter field at the bottom.
final class ActionPanelView: LauncherCardView, NSTextFieldDelegate {
    static let width: CGFloat = 360
    static let headingHeight: CGFloat = 30
    static let rowHeight: CGFloat = 32
    static let filterHeight: CGFloat = 40
    static let listPadding: CGFloat = 4
    static let horizontalInset: CGFloat = 12
    static let placeholder = "search for actions…"
    static let emptyText = "no results"

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
    private let filterRule = RetroRuleView(axis: .horizontal, style: .single)
    private var rowCount = 0
    private var selectedIndex: Int?
    private var hoveredIndex: Int?
    private var colors = AppTheme.missionControl.colors

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
        filterRule.translatesAutoresizingMaskIntoConstraints = true
        filterField.font = RetroFont.body(13)
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
        colors: ThemeColors
    ) {
        self.colors = colors
        applyCardStyle(colors)
        if rows.count != rowCount {
            hoveredIndex = nil
            document.resetHover()
        }
        rowCount = rows.count
        self.selectedIndex = selectedIndex
        headingLabel.attributedStringValue = RetroText.display(title, color: colors.textMuted)
        emptyLabel.attributedStringValue = RetroText.display(Self.emptyText, color: colors.textMuted, alignment: .center)
        filterRule.color = colors.borderSubtle
        filterField.textColor = colors.textPrimary
        filterField.placeholderAttributedString = LauncherText.plain(
            Self.placeholder, font: RetroFont.body(13), color: colors.textMuted
        )
        LauncherText.sync(filterField, to: query)
        if focused {
            (filterField.currentEditor() as? NSTextView)?.insertionPointColor = colors.accent
        }

        document.ensureRowCount(rows.count) { [weak self] row in
            row.onClick = { index in self?.onActionClick?(index) }
        }
        let rowWidth = Self.width - Self.listPadding * 2
        for (index, row) in rows.enumerated() {
            document.rows[index].configure(
                row,
                index: index,
                frame: CGRect(
                    x: Self.listPadding,
                    y: Self.listPadding + CGFloat(index) * Self.rowHeight,
                    width: rowWidth,
                    height: Self.rowHeight
                ),
                isSelected: index == selectedIndex,
                isHovered: index == hoveredIndex,
                colors: colors
            )
        }
    }

    /// Heading, every row (at least one row's height for the empty text), the filter.
    func preferredHeight(maxHeight: CGFloat) -> CGFloat {
        let listHeight = CGFloat(max(1, rowCount)) * Self.rowHeight + Self.listPadding * 2
        return min(maxHeight, Self.headingHeight + listHeight + Retro.hairline + Self.filterHeight)
    }

    func layoutContents() {
        let width = bounds.width
        headingLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset,
            maxX: width - Self.horizontalInset,
            centerY: Self.headingHeight / 2 + 2,
            font: RetroFont.display(11)
        )
        let filterTop = bounds.height - Self.filterHeight
        filterRule.frame = CGRect(x: 0, y: filterTop - Retro.hairline, width: width, height: Retro.hairline)
        let fieldHeight = LauncherText.lineHeight(RetroFont.body(13)) + 2
        filterField.frame = CGRect(
            x: Self.horizontalInset,
            y: (filterTop + (Self.filterHeight - fieldHeight) / 2).rounded(),
            width: width - Self.horizontalInset * 2,
            height: fieldHeight
        )
        let listFrame = CGRect(
            x: 0,
            y: Self.headingHeight,
            width: width,
            height: max(0, filterTop - Retro.hairline - Self.headingHeight)
        )
        scrollView.frame = listFrame
        document.setFrameSize(NSSize(
            width: width,
            height: max(CGFloat(rowCount) * Self.rowHeight + Self.listPadding * 2, listFrame.height)
        ))
        emptyLabel.isHidden = rowCount > 0
        emptyLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset,
            maxX: width - Self.horizontalInset,
            centerY: listFrame.midY,
            font: RetroFont.display(11)
        )
    }

    /// Keeps the selected action whole in view.
    func scrollSelectionIntoView() {
        guard let selected = selectedIndex, rowViews.indices.contains(selected) else { return }
        let frame = rowViews[selected].frame.insetBy(dx: 0, dy: -Self.listPadding)
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

/// One action: title (body 13, `danger` when destructive) and its shortcut keycaps right;
/// the selected one gets `bgSelectedStrong` and the `accent` rail.
final class ActionRowView: LauncherFlippedView {
    static let horizontalInset: CGFloat = 10
    static let keycapHeight: CGFloat = 18

    private(set) var index = 0
    private(set) var title = ""
    private(set) var isSelected = false
    private(set) var isHovered = false
    var onClick: ((Int) -> Void)?

    private let titleLabel = LauncherText.label()
    private let keycaps = KeycapRowView()
    private let rail = LauncherFlippedView()
    private var colors = AppTheme.missionControl.colors

    init() {
        super.init(frame: .zero)
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)
        addSubview(keycaps)
        addSubview(rail)
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
            row.title, font: RetroFont.body(13), color: row.isDestructive ? colors.danger : colors.textPrimary
        )
        if row.keys != keycaps.keys {
            keycaps.configure(keys: row.keys, fontSize: RetroFont.grid, height: Self.keycapHeight, colors: colors)
        }
        applyState()
        layoutContents()
        setAccessibilityLabel(row.title)
        setAccessibilitySelected(isSelected)
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        applyState()
    }

    private func applyState() {
        let fill: NSColor = isSelected ? colors.bgSelectedStrong : (isHovered ? colors.bgOverlay : .clear)
        layer?.backgroundColor = fill.cgColor
        rail.isHidden = !isSelected
        rail.layer?.backgroundColor = colors.accent.cgColor
    }

    private func layoutContents() {
        let centerY = bounds.height / 2
        rail.frame = CGRect(x: 0, y: 0, width: ResultRowView.railWidth, height: bounds.height)
        var trailing = bounds.width - Self.horizontalInset
        keycaps.isHidden = keycaps.keys.isEmpty
        if !keycaps.keys.isEmpty {
            keycaps.frame = CGRect(
                x: trailing - keycaps.preferredWidth,
                y: (centerY - Self.keycapHeight / 2).rounded(),
                width: keycaps.preferredWidth,
                height: Self.keycapHeight
            )
            keycaps.layoutCaps()
            trailing = keycaps.frame.minX - 8
        }
        titleLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset, maxX: trailing, centerY: centerY, font: RetroFont.body(13)
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

// MARK: - Hotkey recorder

/// The hotkey recorder: the item title, the keys so far as display-22 keycaps, the
/// conflicting owner in `danger`, a 2 pt `accent` countdown bar and the hint line.
final class RecorderCardView: LauncherCardView {
    static let width: CGFloat = 380
    static let padding: CGFloat = 20
    static let lineSlot: CGFloat = 16
    static let keycapHeight: CGFloat = 40
    static let barHeight: CGFloat = 2
    static let recordingText = "recording…"

    static func size() -> CGSize {
        CGSize(
            width: width,
            height: padding + lineSlot + 16 + keycapHeight + 12 + lineSlot + 12 + barHeight + 14 + lineSlot + padding
        )
    }

    private let titleLabel = LauncherText.label()
    private let keycaps = KeycapRowView()
    private let recordingLabel = LauncherText.label()
    private let conflictLabel = LauncherText.label()
    private let countdownBar = LauncherFlippedView()
    private let hintLabel = LauncherText.label()
    private var countdown: Double?

    /// The keycaps showing, for tests.
    var shownKeys: [String] { keycaps.keys }
    /// The countdown bar's width (0 while hidden), for tests.
    var countdownWidth: CGFloat { countdownBar.isHidden ? 0 : countdownBar.frame.width }

    init() {
        super.init(frame: .zero)
        for label in [titleLabel, recordingLabel, conflictLabel, hintLabel] {
            label.alignment = .center
        }
        for view: NSView in [titleLabel, keycaps, recordingLabel, conflictLabel, countdownBar, hintLabel] {
            addSubview(view)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Record hotkey")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(itemTitle: String, keys: [String], conflict: String?, countdown: Double?, hint: String, colors: ThemeColors) {
        applyCardStyle(colors)
        self.countdown = countdown
        titleLabel.attributedStringValue = RetroText.display(itemTitle, color: colors.textPrimary, alignment: .center)
        if keys != keycaps.keys {
            keycaps.configure(keys: keys, fontSize: 22, height: Self.keycapHeight, colors: colors)
        }
        recordingLabel.attributedStringValue = RetroText.display(
            Self.recordingText, color: colors.textMuted, size: 22, alignment: .center
        )
        conflictLabel.attributedStringValue = RetroText.display(conflict ?? "", color: colors.danger, alignment: .center)
        countdownBar.layer?.backgroundColor = colors.accent.cgColor
        hintLabel.attributedStringValue = RetroText.display(hint, color: colors.textMuted, alignment: .center)
    }

    func layoutContents() {
        let width = bounds.width
        let minX = Self.padding
        let maxX = width - Self.padding
        var y = Self.padding
        titleLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: RetroFont.display(11))
        y += Self.lineSlot + 16

        let hasKeys = !keycaps.keys.isEmpty
        keycaps.isHidden = !hasKeys
        recordingLabel.isHidden = hasKeys
        if hasKeys {
            let keysWidth = min(keycaps.preferredWidth, maxX - minX)
            keycaps.frame = CGRect(x: ((width - keysWidth) / 2).rounded(), y: y, width: keysWidth, height: Self.keycapHeight)
            keycaps.layoutCaps()
        } else {
            recordingLabel.frame = LauncherText.lineFrame(
                minX: minX, maxX: maxX, centerY: y + Self.keycapHeight / 2, font: RetroFont.display(22)
            )
        }
        y += Self.keycapHeight + 12

        conflictLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: RetroFont.display(11))
        conflictLabel.isHidden = conflictLabel.attributedStringValue.length == 0
        y += Self.lineSlot + 12

        if let countdown {
            let progress = CGFloat(min(max(countdown, 0), 1))
            countdownBar.isHidden = false
            countdownBar.frame = CGRect(x: minX, y: y, width: ((maxX - minX) * progress).rounded(), height: Self.barHeight)
        } else {
            countdownBar.isHidden = true
        }
        y += Self.barHeight + 14

        hintLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: RetroFont.display(11))
    }
}

// MARK: - Alias editor

/// The alias editor: the item title, a bordered body-14 field (framed in `accent` while
/// focused) and the validation error in `danger`.
final class AliasEditorCardView: LauncherCardView, NSTextFieldDelegate {
    static let width: CGFloat = 380
    static let padding: CGFloat = 20
    static let lineSlot: CGFloat = 16
    static let fieldBoxHeight: CGFloat = 32
    static let placeholder = "alias"

    static func size() -> CGSize {
        CGSize(width: width, height: padding + lineSlot + 12 + fieldBoxHeight + 10 + lineSlot + padding)
    }

    let field = LauncherText.inputField()
    /// The text changed.
    var onTextChange: ((String) -> Void)?

    private let titleLabel = LauncherText.label()
    private let fieldBox = LauncherFlippedView()
    private let errorLabel = LauncherText.label()

    init() {
        super.init(frame: .zero)
        field.font = RetroFont.body(14)
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

    func configure(itemTitle: String, text: String, error: String?, focused: Bool, colors: ThemeColors) {
        applyCardStyle(colors)
        titleLabel.attributedStringValue = RetroText.display(itemTitle, color: colors.textPrimary)
        fieldBox.layer?.backgroundColor = colors.bgRaised.cgColor
        fieldBox.layer?.borderColor = (focused ? colors.accent : colors.borderSubtle).cgColor
        fieldBox.layer?.borderWidth = Retro.hairline
        field.textColor = colors.textPrimary
        field.placeholderAttributedString = LauncherText.plain(Self.placeholder, font: RetroFont.body(14), color: colors.textMuted)
        LauncherText.sync(field, to: text)
        if focused {
            (field.currentEditor() as? NSTextView)?.insertionPointColor = colors.accent
        }
        errorLabel.attributedStringValue = RetroText.display(error ?? "", color: colors.danger)
        errorLabel.isHidden = error == nil
    }

    func layoutContents() {
        let minX = Self.padding
        let maxX = bounds.width - Self.padding
        var y = Self.padding
        titleLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: RetroFont.display(11))
        y += Self.lineSlot + 12
        fieldBox.frame = CGRect(x: minX, y: y, width: maxX - minX, height: Self.fieldBoxHeight)
        let fieldHeight = LauncherText.lineHeight(RetroFont.body(14)) + 2
        field.frame = CGRect(
            x: 8,
            y: ((Self.fieldBoxHeight - fieldHeight) / 2).rounded(),
            width: max(0, fieldBox.bounds.width - 16),
            height: fieldHeight
        )
        y += Self.fieldBoxHeight + 10
        errorLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: RetroFont.display(11))
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        LauncherText.swallows(commandSelector)
    }
}

// MARK: - Confirmation

/// "Are you sure?": the title, the message, and "cancel ⎋" / "<confirm> ↵" console keys.
/// Every confirmation guards a destructive command, so the confirm key is lit in `danger`.
final class ConfirmationCardView: LauncherCardView {
    static let width: CGFloat = 400
    static let padding: CGFloat = 20
    static let lineSlot: CGFloat = 16
    static let buttonGap: CGFloat = 8

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private let titleLabel = LauncherText.label()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton: RetroButton
    private let confirmButton: RetroButton
    private var messageHeight: CGFloat = 0

    /// The confirm key's title, for tests.
    var confirmButtonTitle: String { confirmButton.title }

    init() {
        cancelButton = RetroButton(title: "cancel ⎋", theme: .missionControl)
        confirmButton = RetroButton(title: "", theme: .missionControl, kind: .prominent)
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
        titleLabel.attributedStringValue = RetroText.display(title, color: colors.textPrimary)
        let messageText = LauncherText.plain(message, font: RetroFont.body(13), color: colors.textMuted, lineBreakMode: .byWordWrapping)
        messageLabel.attributedStringValue = messageText
        let textWidth = Self.width - Self.padding * 2
        messageHeight = message.isEmpty ? 0 : ceil(messageText.boundingRect(
            with: CGSize(width: textWidth - 4, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height) + 2
        cancelButton.apply(theme: theme)
        confirmButton.apply(theme: Self.dangerTheme(theme))
        confirmButton.title = "\(confirmTitle) ↵"
    }

    func preferredSize() -> CGSize {
        let messageBlock = messageHeight > 0 ? messageHeight + 10 : 0
        return CGSize(
            width: Self.width,
            height: Self.padding + Self.lineSlot + 10 + messageBlock + 8 + Retro.controlHeight + Self.padding
        )
    }

    func layoutContents() {
        let minX = Self.padding
        let maxX = bounds.width - Self.padding
        var y = Self.padding
        titleLabel.frame = LauncherText.lineFrame(minX: minX, maxX: maxX, centerY: y + Self.lineSlot / 2, font: RetroFont.display(11))
        y += Self.lineSlot + 10
        messageLabel.isHidden = messageHeight == 0
        messageLabel.frame = CGRect(x: minX, y: y, width: maxX - minX, height: messageHeight)
        if messageHeight > 0 {
            y += messageHeight + 10
        }
        y += 8
        let confirmWidth = confirmButton.intrinsicContentSize.width
        let cancelWidth = cancelButton.intrinsicContentSize.width
        confirmButton.frame = CGRect(x: maxX - confirmWidth, y: y, width: confirmWidth, height: Retro.controlHeight)
        cancelButton.frame = CGRect(
            x: confirmButton.frame.minX - Self.buttonGap - cancelWidth,
            y: y,
            width: cancelWidth,
            height: Retro.controlHeight
        )
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func confirmClicked() {
        onConfirm?()
    }

    /// `theme` with `danger` as its accent: a prominent `RetroButton` lights in it.
    static func dangerTheme(_ theme: AppTheme) -> AppTheme {
        let colors = theme.colors
        return AppTheme(
            id: "\(theme.id)-danger",
            name: theme.name,
            colors: ThemeColors(
                bgBase: colors.bgBase,
                bgPanel: colors.bgPanel,
                bgRaised: colors.bgRaised,
                bgOverlay: colors.bgOverlay,
                textPrimary: colors.textPrimary,
                textMuted: colors.textMuted,
                accent: colors.danger,
                accentStrong: colors.danger,
                borderSubtle: colors.borderSubtle,
                borderStrong: colors.borderStrong,
                success: colors.success,
                danger: colors.danger,
                blue: colors.blue,
                cyan: colors.cyan,
                yellow: colors.yellow,
                gray: colors.gray
            ),
            terminalColors: theme.terminalColors
        )
    }
}

// MARK: - Output

/// Script output (fullOutput mode) in place of the list: a title row over a selectable,
/// monospace body-12 text view.
final class OutputView: LauncherFlippedView {
    static let titleHeight: CGFloat = 36
    static let horizontalInset: CGFloat = 16

    let textView: NSTextView
    private let scrollView = NSScrollView()
    private let titleLabel = LauncherText.label()
    private let rule = RetroRuleView(axis: .horizontal, style: .single)

    /// The text showing.
    var text: String { textView.string }

    init() {
        textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        super.init(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = RetroFont.body(12)
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
        rule.translatesAutoresizingMaskIntoConstraints = true
        for view: NSView in [titleLabel, rule, scrollView] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, text: String, isError: Bool, colors: ThemeColors) {
        titleLabel.attributedStringValue = RetroText.display(title, color: isError ? colors.danger : colors.textPrimary)
        rule.color = colors.borderSubtle
        textView.textColor = colors.textPrimary
        textView.insertionPointColor = colors.accent
        textView.selectedTextAttributes = [.backgroundColor: colors.bgSelectedStrong]
        if textView.string != text {
            textView.string = text
            textView.textColor = colors.textPrimary
            textView.font = RetroFont.body(12)
            textView.scroll(.zero)
        }
    }

    func layoutContents() {
        titleLabel.frame = LauncherText.lineFrame(
            minX: Self.horizontalInset,
            maxX: bounds.width - Self.horizontalInset,
            centerY: Self.titleHeight / 2,
            font: RetroFont.display(11)
        )
        rule.frame = CGRect(x: 0, y: Self.titleHeight, width: bounds.width, height: Retro.hairline)
        let top = Self.titleHeight + Retro.hairline
        scrollView.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        let contentWidth = scrollView.contentSize.width
        if textView.frame.width != contentWidth {
            textView.setFrameSize(NSSize(width: contentWidth, height: max(textView.frame.height, scrollView.contentSize.height)))
        }
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
}
