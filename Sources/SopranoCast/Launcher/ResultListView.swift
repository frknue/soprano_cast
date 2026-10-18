import AppKit
import SopranoCastCore

/// Root Search's sectioned list: section headers (display 11 with a rule) and 40 pt rows
/// in a scroll view that keeps the selection visible, or the empty text centered. Row
/// views are reused across updates; a selection or hover change only restyles them.
final class ResultListView: LauncherFlippedView {
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 28
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

    func apply(sections: [SectionViewModel], selectedIndex: Int?, emptyText: String?, theme: AppTheme) {
        let colors = theme.colors
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
            let font = RetroFont.display(22)
            emptyLabel.isHidden = false
            emptyLabel.attributedStringValue = RetroText.display(
                emptyText, color: colors.textMuted, size: 22, alignment: .center
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

/// A section title in display 11 `textMuted` followed by a `borderSubtle` rule.
final class SectionHeaderView: LauncherFlippedView {
    static let leadingInset: CGFloat = 12

    private let label = LauncherText.label()
    private let rule = RetroRuleView(axis: .horizontal, style: .single)
    private(set) var title = ""

    init() {
        super.init(frame: .zero)
        rule.translatesAutoresizingMaskIntoConstraints = true
        addSubview(label)
        addSubview(rule)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, colors: ThemeColors) {
        self.title = title
        label.attributedStringValue = RetroText.display(title, color: colors.textMuted)
        rule.color = colors.borderSubtle
        // The title sits a little below the band's middle, close to the rows it heads.
        let centerY = (bounds.height / 2 + 3).rounded()
        let maxX = bounds.width - Self.leadingInset
        let labelWidth = min(LauncherText.width(of: label.attributedStringValue), max(0, maxX - Self.leadingInset))
        label.frame = LauncherText.lineFrame(
            minX: Self.leadingInset, maxX: Self.leadingInset + labelWidth, centerY: centerY, font: RetroFont.display(11)
        )
        let ruleX = label.frame.maxX + 8
        rule.frame = CGRect(x: ruleX, y: centerY, width: max(0, maxX - ruleX), height: Retro.hairline)
        rule.isHidden = rule.frame.width <= 0
    }
}

// MARK: - Row

/// One result: 24 pt icon, title (matched characters in `accent`), alias badge, subtitle,
/// and the trailing accessory; the selected row gets `bgSelectedStrong`, a 2 pt `accent`
/// rail and its hotkey keycaps before the accessory. Text and icon are rebuilt only when
/// the row's content changes.
final class ResultRowView: LauncherFlippedView {
    static let iconSide: CGFloat = 24
    static let railWidth: CGFloat = 2
    static let leadingInset: CGFloat = 12
    static let trailingInset: CGFloat = 12
    static let keycapHeight: CGFloat = 20

    private(set) var index = 0
    private(set) var itemID: ItemID?
    private(set) var isSelected = false
    private(set) var isHovered = false
    /// The keycaps showing (the selected row's hotkey; empty otherwise).
    var shownHotkeyKeys: [String] { keycaps.isHidden ? [] : keycaps.keys }

    var onClick: ((Int, Int) -> Void)?

    private let iconLayer = CALayer()
    private let titleLabel = LauncherText.label()
    private let subtitleLabel = LauncherText.label()
    private let accessoryLabel = LauncherText.label()
    private let aliasChip = BadgeChipView()
    private let keycaps = KeycapRowView()
    private let rail = LauncherFlippedView()
    private var content: Content?
    private var colors = AppTheme.missionControl.colors
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
        addSubview(rail)
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
        isHovered: Bool,
        theme: AppTheme
    ) {
        self.index = index
        itemID = row.id
        colors = theme.colors
        self.isSelected = isSelected
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
        titleLabel.attributedStringValue = LauncherText.title(
            row.title, highlights: row.titleHighlights, font: RetroFont.body(14),
            color: colors.textPrimary, highlight: colors.accent
        )
        subtitleLabel.attributedStringValue = LauncherText.plain(row.subtitle, font: RetroFont.body(12), color: colors.textMuted)
        accessoryLabel.attributedStringValue = LauncherText.plain(
            row.accessory, font: RetroFont.body(12), color: colors.textMuted, alignment: .right
        )
        hasAlias = !(row.alias ?? "").isEmpty
        aliasChip.configure(text: row.alias ?? "", colors: colors)
        keycaps.configure(keys: row.hotkeyKeys, fontSize: RetroFont.grid, height: Self.keycapHeight, colors: colors)
    }

    /// Fill and rail: everything selection and hover change.
    private func applyState() {
        let fill: NSColor = isSelected ? colors.bgSelectedStrong : (isHovered ? colors.bgOverlay : .clear)
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = Retro.cornerRadius
        rail.isHidden = !isSelected
        rail.layer?.backgroundColor = colors.accent.cgColor
    }

    private func layoutContents() {
        let height = bounds.height
        let centerY = height / 2
        rail.frame = CGRect(x: 0, y: 0, width: Self.railWidth, height: height)
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
            minX: trailing - accessoryWidth, maxX: trailing, centerY: centerY, font: RetroFont.body(12)
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

        let leading = Self.leadingInset + Self.iconSide + 10
        let titleWidth = min(LauncherText.width(of: titleLabel.attributedStringValue), max(0, trailing - leading))
        titleLabel.frame = LauncherText.lineFrame(
            minX: leading, maxX: leading + titleWidth, centerY: centerY, font: RetroFont.body(14)
        )
        var x = titleLabel.frame.maxX + 6
        let chipFits = hasAlias && x + aliasChip.preferredWidth <= trailing
        aliasChip.isHidden = !chipFits
        if chipFits {
            aliasChip.frame = CGRect(
                x: x,
                y: ((height - BadgeChipView.height) / 2).rounded(),
                width: aliasChip.preferredWidth,
                height: BadgeChipView.height
            )
            x = aliasChip.frame.maxX + 8
        } else {
            x += 2
        }
        let subtitleWidth = max(0, trailing - x)
        subtitleLabel.isHidden = subtitleLabel.attributedStringValue.length == 0 || subtitleWidth < 24
        subtitleLabel.frame = LauncherText.lineFrame(minX: x, maxX: trailing, centerY: centerY, font: RetroFont.body(12))
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
