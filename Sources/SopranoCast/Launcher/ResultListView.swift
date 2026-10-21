import AppKit
import SopranoCastCore

/// Root Search's sectioned list: eyebrow section headers and 40 pt rows in a scroll view
/// that keeps the selection visible, or the empty text centered. Row views are reused
/// across updates; a selection or hover change only restyles them.
final class ResultListView: LauncherFlippedView {
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 26
    /// Extra space above a header that follows a row.
    static let headerGap: CGFloat = 6
    static let horizontalInset: CGFloat = 8
    static let verticalInset: CGFloat = 6

    /// A row was clicked: flat index, click count.
    var onRowClick: ((Int, Int) -> Void)?

    /// The row views in flat order.
    var rowViews: [ResultRowView] { document.rows }
    var headerViews: [SectionHeaderView] { document.headers }
    var isShowingEmptyText: Bool { !emptyLabel.isHidden }

    /// How many whole rows fit in a list area `height` points tall.
    static func visibleRowCount(height: CGFloat) -> Int {
        max(1, Int((height - verticalInset * 2) / rowHeight))
    }

    private let scrollView = NSScrollView()
    private let document = ResultListDocumentView()
    private let emptyLabel = LauncherText.label()
    private var rowIDs: [ItemID] = []
    private var selectedIndex: Int?
    private var isFocused = true
    private var hoveredIndex: Int?
    /// The top of each section (its header, or its first row without one), keyed by the
    /// flat index of the section's first row.
    private var sectionTops: [Int: CGFloat] = [:]

    init() {
        super.init(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // No scroller chrome: rows scroll with the wheel and follow the selection.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = document
        document.onHover = { [weak self] index in self?.setHovered(index) }
        emptyLabel.alignment = .center
        addSubview(scrollView)
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `isFocused`: Root Search has the keyboard (pill and pencil tick on the selection;
    /// a muted pill while an overlay holds it).
    func apply(sections: [SectionViewModel], selectedIndex: Int?, isFocused: Bool, emptyText: String?, theme: AppTheme) {
        let colors = theme.colors
        self.isFocused = isFocused
        let shown = sections.filter { !$0.rows.isEmpty }
        let ids = shown.flatMap { $0.rows.map(\.id) }
        let rowsChanged = ids != rowIDs
        if rowsChanged {
            hoveredIndex = nil
            document.resetHover()
        }
        rowIDs = ids
        self.selectedIndex = selectedIndex
        scrollView.frame = bounds

        document.ensure(rowCount: ids.count, headerCount: shown.filter { !$0.title.isEmpty }.count) { [weak self] row in
            row.onClick = { index, clickCount in self?.onRowClick?(index, clickCount) }
        }
        let width = bounds.width - Self.horizontalInset * 2
        var y = Self.verticalInset
        var flatIndex = 0
        var headerIndex = 0
        sectionTops = [:]
        for section in shown {
            sectionTops[flatIndex] = y
            if !section.title.isEmpty {
                if flatIndex > 0 {
                    y += Self.headerGap
                    sectionTops[flatIndex] = y
                }
                let header = document.headers[headerIndex]
                header.frame = CGRect(x: Self.horizontalInset, y: y, width: width, height: Self.headerHeight)
                header.configure(title: section.title, colors: colors)
                headerIndex += 1
                y += Self.headerHeight
            }
            for row in section.rows {
                document.rows[flatIndex].configure(
                    row,
                    index: flatIndex,
                    frame: CGRect(x: Self.horizontalInset, y: y, width: width, height: Self.rowHeight),
                    isSelected: flatIndex == selectedIndex,
                    isFocused: isFocused,
                    isHovered: flatIndex == hoveredIndex,
                    theme: theme
                )
                flatIndex += 1
                y += Self.rowHeight
            }
        }
        document.setFrameSize(NSSize(width: bounds.width, height: max(y + Self.verticalInset, bounds.height)))
        if rowsChanged {
            scroll(toY: 0)
        }

        if ids.isEmpty, let emptyText {
            let font = ChromeFont.empty
            emptyLabel.isHidden = false
            emptyLabel.attributedStringValue = ChromeText.attributed(
                emptyText, font: font, color: colors.textMuted, alignment: .center
            )
            emptyLabel.frame = LauncherText.lineFrame(
                minX: Self.horizontalInset, maxX: bounds.width - Self.horizontalInset, centerY: bounds.midY, font: font
            )
        } else {
            emptyLabel.isHidden = true
        }
    }

    /// Keeps the selected row whole in view, moving as little as possible; a section's
    /// first row brings its header along, and the very first row scrolls to the top.
    func scrollSelectionIntoView() {
        guard let selected = selectedIndex, rowViews.indices.contains(selected) else { return }
        var target = rowViews[selected].frame
        if selected == 0 {
            target = CGRect(x: target.minX, y: 0, width: target.width, height: target.maxY)
        } else if let top = sectionTops[selected] {
            target = CGRect(x: target.minX, y: top, width: target.width, height: target.maxY - top)
        }
        let visible = scrollView.contentView.bounds
        guard target.minY < visible.minY || target.maxY > visible.maxY else { return }
        scroll(toY: target.minY < visible.minY ? target.minY : target.maxY - visible.height)
    }

    private func scroll(toY y: CGFloat) {
        let maxY = max(0, document.frame.height - scrollView.contentView.bounds.height)
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
}

/// The list's document view: owns the header and row views and reports hover over rows.
final class ResultListDocumentView: HoverContainerView {
    private(set) var rows: [ResultRowView] = []
    private(set) var headers: [SectionHeaderView] = []

    override var hoverTargets: [NSView] { rows }

    /// Adds or removes views at the end so exactly these counts exist; `prepare` runs once
    /// for each new row view.
    func ensure(rowCount: Int, headerCount: Int, prepare: (ResultRowView) -> Void) {
        while rows.count > rowCount {
            rows.removeLast().removeFromSuperview()
        }
        while rows.count < rowCount {
            let row = ResultRowView()
            prepare(row)
            addSubview(row)
            rows.append(row)
        }
        while headers.count > headerCount {
            headers.removeLast().removeFromSuperview()
        }
        while headers.count < headerCount {
            let header = SectionHeaderView()
            addSubview(header)
            headers.append(header)
        }
    }
}

// MARK: - Section header

/// A section heading: an eyebrow (SF 11 Semibold, UPPERCASE, muted, no rule). A quoted
/// query in the title (`Use “chr” with…`) keeps its case at Medium weight.
final class SectionHeaderView: LauncherFlippedView {
    static let leadingInset: CGFloat = 12

    private let label = LauncherText.label()
    private(set) var title = ""

    init() {
        super.init(frame: .zero)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, colors: ThemeColors) {
        self.title = title
        label.attributedStringValue = Self.eyebrow(title, color: colors.textMuted)
        let maxX = bounds.width - Self.leadingInset
        label.frame = LauncherText.lineFrame(
            minX: Self.leadingInset, maxX: maxX, centerY: (bounds.height / 2).rounded(), font: ChromeFont.eyebrow
        )
    }

    /// The title uppercased, except a `“…”` quote, which stays verbatim at Medium weight.
    static func eyebrow(_ title: String, color: NSColor) -> NSAttributedString {
        guard let open = title.firstIndex(of: "“"), let close = title.lastIndex(of: "”"), open < close else {
            return ChromeText.eyebrow(title, color: color)
        }
        let quoteEnd = title.index(after: close)
        let string = NSMutableAttributedString(attributedString: ChromeText.eyebrow(String(title[..<open]), color: color))
        string.append(ChromeText.attributed(
            String(title[open..<quoteEnd]), font: ChromeFont.sans(size: 11, weight: .medium), color: color
        ))
        string.append(ChromeText.eyebrow(String(title[quoteEnd...]), color: color))
        return string
    }
}

// MARK: - Row

/// One result: 24 pt icon, title (SF 13; matches Semibold, in `matchOnSelection` on the
/// selected row only), alias chip, subtitle (meta; SF Mono for paths) and the trailing
/// hotkey caps and accessory. Selection is Folio's pill (+ pencil tick while Root Search
/// has the keyboard); hover a `hover` pill. Text and icon are rebuilt only when the row's
/// content changes.
final class ResultRowView: LauncherFlippedView {
    static let iconSide: CGFloat = 24
    static let leadingInset: CGFloat = 12
    static let trailingInset: CGFloat = 12
    static let gap: CGFloat = 12
    static let keycapHeight: CGFloat = Chrome.keycapHeight

    private(set) var index = 0
    private(set) var itemID: ItemID?
    private(set) var isSelected = false
    private(set) var isFocused = true
    private(set) var isHovered = false
    /// The keycaps showing (the selected row's hotkey; empty otherwise).
    var shownHotkeyKeys: [String] { keycaps.isHidden ? [] : keycaps.keys }
    /// The title as drawn (match weight and color), for tests.
    var titleText: NSAttributedString { titleLabel.attributedStringValue }

    var onClick: ((Int, Int) -> Void)?

    private let iconLayer = CALayer()
    private let titleLabel = LauncherText.label()
    private let subtitleLabel = LauncherText.label()
    private let accessoryLabel = LauncherText.label()
    private let aliasChip = BadgeChipView()
    private let keycaps = KeycapRowView()
    private var content: Content?
    private var row: RowViewModel?
    private var colors = AppTheme.folioPaper.colors
    private var hasAlias = false

    /// What the row shows apart from selection and hover; a change rebuilds text and icon.
    private struct Content: Equatable {
        var id: ItemID
        var title: String
        var titleHighlights: [NSRange]
        var subtitle: String
        var accessory: String
        var alias: String?
        var hotkeyKeys: [String]
        var icon: ObjectIdentifier
        var themeID: String
    }

    init() {
        super.init(frame: .zero)
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.minificationFilter = .trilinear
        iconLayer.contentsScale = 2
        layer?.addSublayer(iconLayer)
        accessoryLabel.alignment = .right
        for label in [titleLabel, subtitleLabel, accessoryLabel] {
            label.setAccessibilityElement(false)
        }
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(accessoryLabel)
        addSubview(aliasChip)
        addSubview(keycaps)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        _ row: RowViewModel,
        index: Int,
        frame: CGRect,
        isSelected: Bool,
        isFocused: Bool,
        isHovered: Bool,
        theme: AppTheme
    ) {
        self.index = index
        itemID = row.id
        colors = theme.colors
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.row = row
        self.isHovered = isHovered
        self.frame = frame
        let content = Content(
            id: row.id,
            title: row.title,
            titleHighlights: row.titleHighlights,
            subtitle: row.subtitle,
            accessory: row.accessory,
            alias: row.alias,
            hotkeyKeys: row.hotkeyKeys,
            icon: ObjectIdentifier(row.icon),
            themeID: theme.id
        )
        if content != self.content {
            self.content = content
            applyContent(row)
        }
        applyState()
        layoutContents()
        setAccessibilityLabel(row.accessory.isEmpty ? row.title : "\(row.title), \(row.accessory)")
        setAccessibilitySelected(isSelected)
    }

    /// Restyles for a hover change; nothing else redraws.
    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        applyState()
    }

    private func applyContent(_ row: RowViewModel) {
        iconLayer.contents = LauncherText.cgImage(row.icon, side: Self.iconSide, scale: iconLayer.contentsScale)
        let isPath = row.subtitle.hasPrefix("/") || row.subtitle.hasPrefix("~")
        subtitleLabel.attributedStringValue = LauncherText.plain(
            row.subtitle, font: isPath ? ChromeFont.monoSmall : ChromeFont.meta, color: colors.textMuted
        )
        accessoryLabel.attributedStringValue = LauncherText.plain(
            row.accessory, font: ChromeFont.meta, color: colors.textMuted, alignment: .right
        )
        hasAlias = !(row.alias ?? "").isEmpty
        aliasChip.configure(text: row.alias ?? "", colors: colors)
        keycaps.configure(keys: row.hotkeyKeys, colors: colors)
    }

    /// The pill and the title's match color: everything selection and hover change.
    private func applyState() {
        if let row {
            titleLabel.attributedStringValue = LauncherText.title(
                row.title,
                highlights: row.titleHighlights,
                font: ChromeFont.row,
                color: colors.textPrimary,
                matchFont: ChromeFont.sans(size: 13, weight: .semibold),
                matchColor: isSelected ? colors.matchOnSelection : colors.textPrimary
            )
        }
        needsDisplay = true
    }

    /// The Folio row pill; the row frame already sits inside the list's inset.
    var pillStyle: ChromeSelectionPill.Style {
        if isSelected { return isFocused ? .selected : .selectedUnfocused }
        return isHovered ? .hover : .none
    }

    override func draw(_ dirtyRect: NSRect) {
        ChromeSelectionPill.draw(pillStyle, in: bounds, colors: colors, inset: 0)
    }

    private func layoutContents() {
        let height = bounds.height
        let centerY = height / 2
        iconLayer.frame = CGRect(
            x: Self.leadingInset,
            y: ((height - Self.iconSide) / 2).rounded(),
            width: Self.iconSide,
            height: Self.iconSide
        )

        var trailing = bounds.width - Self.trailingInset
        let accessoryWidth = min(
            LauncherText.width(of: accessoryLabel.attributedStringValue),
            (bounds.width * 0.35).rounded()
        )
        accessoryLabel.isHidden = accessoryWidth <= 0
        accessoryLabel.frame = LauncherText.lineFrame(
            minX: trailing - accessoryWidth, maxX: trailing, centerY: centerY, font: ChromeFont.meta
        )
        if accessoryWidth > 0 {
            trailing -= accessoryWidth + 10
        }

        let showsKeys = isSelected && !keycaps.keys.isEmpty
        keycaps.isHidden = !showsKeys
        if showsKeys {
            keycaps.frame = CGRect(
                x: trailing - keycaps.preferredWidth,
                y: ((height - Self.keycapHeight) / 2).rounded(),
                width: keycaps.preferredWidth,
                height: Self.keycapHeight
            )
            keycaps.layoutCaps()
            trailing -= keycaps.preferredWidth + 10
        }

        let leading = Self.leadingInset + Self.iconSide + Self.gap
        let titleWidth = min(LauncherText.width(of: titleLabel.attributedStringValue), max(0, trailing - leading))
        titleLabel.frame = LauncherText.lineFrame(
            minX: leading, maxX: leading + titleWidth, centerY: centerY, font: ChromeFont.row
        )
        // Label frames carry 2 pt of cell padding on each side: 4 here reads as 8.
        var x = titleLabel.frame.maxX + 4
        let chipFits = hasAlias && x + aliasChip.preferredWidth <= trailing
        aliasChip.isHidden = !chipFits
        if chipFits {
            aliasChip.frame = CGRect(
                x: x + 2,
                y: ((height - BadgeChipView.height) / 2).rounded(),
                width: aliasChip.preferredWidth,
                height: BadgeChipView.height
            )
            x = aliasChip.frame.maxX + 6
        }
        let subtitleWidth = max(0, trailing - x)
        subtitleLabel.isHidden = subtitleLabel.attributedStringValue.length == 0 || subtitleWidth < 24
        subtitleLabel.frame = LauncherText.lineFrame(minX: x, maxX: trailing, centerY: centerY + 1, font: ChromeFont.meta)
    }

    // MARK: - Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) && !isHidden ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(index, event.clickCount)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(index, 2)
        return true
    }
}
