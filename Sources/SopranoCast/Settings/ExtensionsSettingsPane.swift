import AppKit
import SopranoCastCore

/// Extensions (Raycast's): every command grouped like Raycast's table — name, type, alias,
/// hotkey, enabled — with a filter, and a detail pane for the selected command (favorite,
/// fallback, quicklink fields) or group (application and script folders, a new quicklink,
/// window management).
@MainActor
final class ExtensionsSettingsPane: NSView, SettingsPane, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    weak var host: SettingsHost?

    /// What the detail pane shows.
    enum Selection: Equatable {
        case group(ExtensionGroup)
        case item(ItemID)
    }

    private enum Line {
        case group(ExtensionSection)
        case item(ExtensionRow)
    }

    private enum Column: String, CaseIterable {
        case name, type, alias, hotkey, enabled

        /// Sentence case; the header sets it in capitals.
        var title: String {
            switch self {
            case .name: "Name"
            case .type: "Type"
            case .alias: "Alias"
            case .hotkey: "Hotkey"
            case .enabled: "Enabled"
            }
        }
        /// Each column after Name carries the 12 pt gap before it (`.table` column-gap);
        /// Enabled also carries the table's 12 pt trailing padding.
        var width: CGFloat {
            switch self {
            case .name: 220
            case .type: 12 + 120
            case .alias: 12 + 76
            case .hotkey: 12 + 108
            case .enabled: 12 + 56 + 12
            }
        }
    }

    /// Leading padding of the table's first column (`.table-head` / `.table-group`).
    static let tableLeading: CGFloat = 16
    /// The gap before every other column.
    static let columnGap: CGFloat = 12

    static let detailWidth: CGFloat = 320
    /// Pop-ups and fields in the detail pane, leaving their labels room.
    static let detailControlWidth: CGFloat = 140
    static let topBarHeight: CGFloat = 52
    static let groupRowHeight: CGFloat = 28
    static let itemRowHeight: CGFloat = 32

    static let gapChoices: [(Int, String)] = [
        (0, "None"), (4, "4 points"), (8, "8 points"), (12, "12 points"), (16, "16 points"), (24, "24 points"), (32, "32 points"),
    ]
    static let halvesChoices: [(HalvesBehavior, String)] = [
        (.stay, "Don't cycle"),
        (.cycleSizes, "Cycle ½, ⅔ and ⅓"),
        (.moveToDisplay, "Move to next display"),
    ]

    private let topBar = LayerView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let filterField = SettingsField(theme: AppTheme.folioPaper, placeholder: "search commands…", symbolName: "magnifyingglass")
    private let countLabel = NSTextField(labelWithString: "")
    private let header = ExtensionsHeaderView()
    private let scrollView = NSScrollView()
    private let table = ExtensionsTableView()
    private let rule = ChromeRuleView(axis: .vertical)
    private let detail = SettingsScrollColumn(
        maxWidth: 10_000,
        spacing: 20,
        insets: NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    )

    private var lines: [Line] = []
    private var collapsed: Set<ExtensionGroup> = []
    private(set) var selection: Selection?
    private(set) var filter = ""
    /// Rebuilding the table mid-way through its own selection change would recurse.
    private var isReloadingTable = false

    // Detail controls read on Save.
    private var quicklinkForm: QuicklinkFormView?
    private var detailAliasField: NSTextField?
    /// The values behind the gap pop-up (a custom one is appended).
    private var gapValues: [Int] = []

    init() {
        super.init(frame: .zero)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Reloading

    func reload() {
        guard let host else { return }
        applyTheme(host.theme)
        if case .item(let id)? = selection, !host.items.contains(where: { $0.id == id }) {
            selection = nil
        }
        reloadTable()
        // A field being typed in keeps its text; the edit lands when it ends.
        if !isEditingDetail {
            reloadDetail()
        }
    }

    /// Remote icons arrived: redraws the name column.
    func reloadIcons() {
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)), columnIndexes: [0])
    }

    /// Lays the table out so an offscreen render draws its rows.
    func prepareForRender() {
        layoutSubtreeIfNeeded()
        fitNameColumn()
        table.tile()
        if let row = selectedLineIndex {
            table.scrollRowToVisible(row)
        }
        scrollView.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        fitNameColumn()
    }

    /// Name takes what the fixed columns leave of the visible width, so Enabled never
    /// slides under the scroller or past the splitter.
    private func fitNameColumn() {
        guard let name = table.tableColumns.first else { return }
        let fixed = Column.allCases.dropFirst().reduce(0) { $0 + $1.width }
        let width = max(name.minWidth, scrollView.contentSize.width - fixed)
        if abs(name.width - width) >= 0.5 {
            name.width = width
        }
    }

    /// Shows `selection` in the table (expanding its group, clearing a filter that hides it)
    /// and the detail pane.
    func select(_ selection: Selection) {
        self.selection = selection
        if case .item(let id) = selection, let group = host?.items.first(where: { $0.id == id })?.kind.flatMap(ExtensionGroup.init(kind:)) {
            collapsed.remove(group)
            if !lines.contains(where: { if case .item(let row) = $0 { row.item.id == id } else { false } }) {
                setFilter("")
            }
        }
        reloadTable()
        if let row = selectedLineIndex {
            table.scrollRowToVisible(row)
        }
        reloadDetail()
    }

    func setFilter(_ text: String) {
        filter = text
        if filterField.stringValue != text {
            filterField.stringValue = text
        }
        reloadTable()
    }

    /// The listed rows, "group:<name>" or the item id, for the harness report.
    var listedIDs: [String] {
        lines.map { line in
            switch line {
            case .group(let section): "group:\(section.group.rawValue)"
            case .item(let row): row.item.id.rawValue
            }
        }
    }

    /// The commands table, for tests (focus and hover).
    var tableView: ExtensionsTableView { table }

    /// The pill the row of `id` draws (nil when it is not laid out), for tests.
    func pillStyle(of id: String) -> ChromeSelectionPill.Style? {
        guard let index = listedIDs.firstIndex(of: id) else { return nil }
        return (table.rowView(atRow: index, makeIfNecessary: true) as? ExtensionsRowView)?.pillStyle
    }

    private var selectedLineIndex: Int? {
        guard let selection else { return nil }
        return lines.firstIndex { line in
            switch (line, selection) {
            case (.group(let section), .group(let group)): section.group == group
            case (.item(let row), .item(let id)): row.item.id == id
            default: false
            }
        }
    }

    private var isEditingDetail: Bool {
        guard let editor = window?.firstResponder as? NSText, let field = editor.delegate as? NSView else { return false }
        return field.isDescendant(of: detail)
    }

    private func reloadTable() {
        guard let host else { return }
        let sections = ExtensionsTable.sections(items: host.items, settings: host.settings, filter: filter)
        lines = sections.flatMap { section -> [Line] in
            let isCollapsed = filter.isEmpty && collapsed.contains(section.group)
            return [.group(section)] + (isCollapsed ? [] : section.rows.map(Line.item))
        }
        let commands = sections.reduce(0) { $0 + $1.rows.count }
        countLabel.setChromeText(
            "\(commands) \(commands == 1 ? "command" : "commands")",
            font: ChromeFont.count,
            color: host.theme.colors.textMuted
        )
        isReloadingTable = true
        table.reloadData()
        if let row = selectedLineIndex {
            table.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        isReloadingTable = false
        header.needsDisplay = true
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        lines.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = lines[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .group = lines[row] { return Self.groupRowHeight }
        return Self.itemRowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ExtensionsRowView()
        view.colors = host?.theme.colors
        view.isHovered = row == table.hoveredRow
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let host else { return nil }
        let chrome = SettingsChrome(theme: host.theme)
        switch lines[row] {
        case .group(let section):
            let isCollapsed = filter.isEmpty && collapsed.contains(section.group)
            return GroupCellView(section: section, collapsed: isCollapsed, chrome: chrome, target: self, toggle: #selector(toggleGroup(_:)), tag: row)
        case .item(let extensionRow):
            guard let identifier = tableColumn?.identifier.rawValue, let column = Column(rawValue: identifier) else { return nil }
            let isSelected = selection == .item(extensionRow.item.id)
            return cell(column, for: extensionRow, row: row, isSelected: isSelected, chrome: chrome, icons: host.icons)
        }
    }

    private func cell(_ column: Column, for row: ExtensionRow, row index: Int, isSelected: Bool, chrome: SettingsChrome, icons: IconProviding) -> NSView {
        let colors = chrome.colors
        let container = NSTableCellView()
        let content: NSView
        switch column {
        case .name:
            let icon = NSImageView()
            icon.image = icons.image(for: row.item.icon, size: 18)
            icon.imageScaling = .scaleProportionallyUpOrDown
            let title = chrome.lineLabel(row.item.title, color: row.isEnabled ? colors.textPrimary : colors.textMuted, font: ChromeFont.row)
            let stack = chrome.hstack([icon, title], spacing: 8)
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            content = stack
        case .type:
            content = chrome.lineLabel(row.typeLabel, color: colors.textMuted)
        case .alias:
            let field = SettingsTextField(string: row.alias ?? "")
            ChromeFieldView.styleEmbedded(field, colors: colors)
            field.colors = colors
            field.textColor = colors.textMuted
            field.isEditable = true
            field.delegate = self
            field.tag = index
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.placeholderAttributedString = ChromeText.attributed(
                isSelected ? "add alias" : "",
                font: ChromeFont.label,
                color: colors.textMuted
            )
            field.setAccessibilityLabel("Alias of \(row.item.title)")
            content = field
        case .hotkey:
            let button = HotkeyButton(
                keycaps: row.hotkey.map(KeyboardLayout.caps(for:)) ?? [],
                theme: chrome.theme,
                style: .small,
                target: self,
                action: #selector(recordRowHotkey(_:))
            )
            button.tag = index
            button.placeholder = "Record"
            button.showsPlaceholder = isSelected
            content = button
        case .enabled:
            let box = chrome.tableCheckbox(isOn: row.isEnabled, accessibilityLabel: "Show \(row.item.title) in Root Search", target: self, action: #selector(enabledChanged(_:)))
            box.tag = index
            content = box
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        var constraints = [content.centerYAnchor.constraint(equalTo: container.centerYAnchor)]
        switch column {
        case .enabled:
            constraints.append(content.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        case .name:
            constraints += [
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.tableLeading),
                content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            ]
        case .type, .alias, .hotkey:
            constraints += [
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.columnGap),
                content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            ]
            if column == .alias {
                constraints.append(content.trailingAnchor.constraint(equalTo: container.trailingAnchor))
            }
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloadingTable else { return }
        let row = table.selectedRow
        let previous = selectedLineIndex
        guard lines.indices.contains(row) else { return }
        switch lines[row] {
        case .group(let section): selection = .group(section.group)
        case .item(let extensionRow): selection = .item(extensionRow.item.id)
        }
        // The alias and hotkey placeholders show on the selected row only.
        let changed = IndexSet([previous, row].compactMap { $0 }.filter { lines.indices.contains($0) })
        table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        reloadDetail()
    }

    // MARK: - Text fields

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === filterField.field else { return }
        setFilter(field.stringValue)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field !== filterField.field else { return }
        if field === detailAliasField, case .item(let id)? = selection {
            setAlias(field.stringValue, for: id)
        } else if field.isDescendant(of: table), lines.indices.contains(field.tag), case .item(let row) = lines[field.tag] {
            setAlias(field.stringValue, for: row.item.id)
        }
    }

    // MARK: - Edits

    /// Saves a lowercased, trimmed alias, removes it when blank, and refuses characters
    /// other than a–z, 0–9 and spaces.
    func setAlias(_ text: String, for id: ItemID) {
        guard let host else { return }
        let alias = text.lowercased().trimmingCharacters(in: .whitespaces)
        let current = host.settings.aliases[id]
        guard AliasText.isValid(alias) else {
            host.showStatus(AliasText.charactersError, isError: true)
            reload()
            return
        }
        if alias.isEmpty {
            if current != nil {
                host.apply([.remove(["aliases", id.rawValue])])
            }
        } else if alias != current {
            host.apply([.set(alias, ["aliases", id.rawValue])])
        } else {
            reload()
        }
    }

    func setEnabled(_ enabled: Bool, for id: ItemID) {
        guard let host else { return }
        host.apply([.set(host.settings.disabledIDs(setting: id, enabled: enabled), ["disabled"])])
    }

    func setFavorite(_ favorite: Bool, for id: ItemID) {
        guard let host, host.settings.favorites.contains(id) != favorite else { return }
        host.apply([.set(host.settings.favoriteIDs(toggling: id), ["favorites"])])
    }

    func setFallback(_ fallback: Bool, for id: ItemID) {
        guard let host, host.settings.fallbacks.contains(id) != fallback else { return }
        host.apply([.set(host.settings.fallbackIDs(toggling: id), ["fallbacks"])])
    }

    /// Creates a quicklink with an id made from its name and selects it.
    func createQuicklink(_ fields: QuicklinkFields) {
        guard let host else { return }
        if let problem = fields.problem {
            host.showStatus(problem, isError: true)
            return
        }
        let id = QuicklinkID.make(for: fields.name, existing: Set(host.settings.quicklinks.map(\.id)))
        if host.apply([.quicklink(id: id, fields: fields)]) {
            select(.item(ItemID(kind: .quicklink, key: id)))
            host.showStatus("Created \(fields.name.trimmingCharacters(in: .whitespaces))", isError: false)
        }
    }

    func saveQuicklink(id: String, fields: QuicklinkFields) {
        guard let host else { return }
        if let problem = fields.problem {
            host.showStatus(problem, isError: true)
            return
        }
        if host.apply([.quicklink(id: id, fields: fields)]) {
            host.showStatus("Saved \(fields.name.trimmingCharacters(in: .whitespaces))", isError: false)
        }
    }

    /// Deletes a quicklink with its hotkey, alias and list entries, so nothing points at it.
    func deleteQuicklink(id: String) {
        guard let host else { return }
        let itemID = ItemID(kind: .quicklink, key: id)
        let settings = host.settings
        var edits: [SettingsEdit] = [.quicklink(id: id, fields: nil)]
        if settings.hotkeys[itemID] != nil { edits.append(.remove(["hotkeys", itemID.rawValue])) }
        if settings.aliases[itemID] != nil { edits.append(.remove(["aliases", itemID.rawValue])) }
        if settings.favorites.contains(itemID) { edits.append(.set(settings.favoriteIDs(toggling: itemID), ["favorites"])) }
        if settings.fallbacks.contains(itemID) { edits.append(.set(settings.fallbackIDs(toggling: itemID), ["fallbacks"])) }
        if settings.disabled.contains(itemID) { edits.append(.set(settings.disabledIDs(setting: itemID, enabled: true), ["disabled"])) }
        selection = .group(.quicklinks)
        host.apply(edits)
    }

    /// Adds a folder to `scriptDirectories` or `applicationDirectories`.
    func addFolder(_ path: String, to group: ExtensionGroup) {
        guard let host, let key = Self.directoriesKey(group) else { return }
        let current = Self.directories(group, in: host.settings)
        guard !current.contains(path) else { return }
        host.apply([.set(current + [path], [key])])
    }

    func removeFolder(at index: Int, from group: ExtensionGroup) {
        guard let host, let key = Self.directoriesKey(group) else { return }
        var current = Self.directories(group, in: host.settings)
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        host.apply([.set(current, [key])])
    }

    private static func directoriesKey(_ group: ExtensionGroup) -> String? {
        switch group {
        case .applications: "applicationDirectories"
        case .scriptCommands: "scriptDirectories"
        default: nil
        }
    }

    private static func directories(_ group: ExtensionGroup, in settings: CastSettings) -> [String] {
        group == .applications ? settings.applicationDirectories : settings.scriptDirectories
    }

    // MARK: - Actions

    @objc private func toggleGroup(_ sender: NSButton) {
        guard lines.indices.contains(sender.tag), case .group(let section) = lines[sender.tag] else { return }
        if collapsed.contains(section.group) {
            collapsed.remove(section.group)
        } else {
            collapsed.insert(section.group)
        }
        reloadTable()
    }

    @objc private func recordRowHotkey(_ sender: NSButton) {
        guard lines.indices.contains(sender.tag), case .item(let row) = lines[sender.tag] else { return }
        if selection != .item(row.item.id) {
            select(.item(row.item.id))
        }
        host?.recordHotkey(for: .item(row.item.id), title: row.item.title)
    }

    @objc private func enabledChanged(_ sender: ChromeCheckbox) {
        guard lines.indices.contains(sender.tag), case .item(let row) = lines[sender.tag] else { return }
        setEnabled(sender.state == .on, for: row.item.id)
    }

    @objc private func detailRecordHotkey() {
        guard case .item(let id)? = selection, let item = host?.items.first(where: { $0.id == id }) else { return }
        host?.recordHotkey(for: .item(id), title: item.title)
    }

    @objc private func detailEnabledChanged(_ sender: ChromeSwitch) {
        guard case .item(let id)? = selection else { return }
        setEnabled(sender.state == .on, for: id)
    }

    @objc private func detailFavoriteChanged(_ sender: ChromeSwitch) {
        guard case .item(let id)? = selection else { return }
        setFavorite(sender.state == .on, for: id)
    }

    @objc private func detailFallbackChanged(_ sender: ChromeSwitch) {
        guard case .item(let id)? = selection else { return }
        setFallback(sender.state == .on, for: id)
    }

    @objc private func createQuicklinkClicked() {
        guard let form = quicklinkForm else { return }
        createQuicklink(form.fields)
    }

    @objc private func saveQuicklinkClicked() {
        guard case .item(let id)? = selection, let form = quicklinkForm else { return }
        saveQuicklink(id: id.key, fields: form.fields)
    }

    @objc private func deleteQuicklinkClicked() {
        guard case .item(let id)? = selection else { return }
        deleteQuicklink(id: id.key)
    }

    @objc private func addFolderClicked() {
        guard case .group(let group)? = selection else { return }
        host?.chooseFolder { [weak self] path in
            self?.addFolder(path, to: group)
        }
    }

    @objc private func removeFolderClicked(_ sender: NSButton) {
        guard case .group(let group)? = selection else { return }
        removeFolder(at: sender.tag, from: group)
    }

    @objc private func gapChanged(_ sender: NSPopUpButton) {
        guard gapValues.indices.contains(sender.indexOfSelectedItem) else { return }
        host?.apply([.set(gapValues[sender.indexOfSelectedItem], ["windowManagement", "gap"])])
    }

    @objc private func halvesChanged(_ sender: NSPopUpButton) {
        guard Self.halvesChoices.indices.contains(sender.indexOfSelectedItem) else { return }
        host?.apply([.set(Self.halvesChoices[sender.indexOfSelectedItem].0.rawValue, ["windowManagement", "halves"])])
    }

    // MARK: - Detail pane

    private func reloadDetail() {
        guard let host else { return }
        let chrome = SettingsChrome(theme: host.theme)
        quicklinkForm = nil
        detailAliasField = nil
        switch selection {
        case .item(let id)?:
            guard let item = host.items.first(where: { $0.id == id }) else {
                detail.setContent([chrome.wrappingLabel("Select a command to see its settings.")])
                return
            }
            detail.setContent(itemDetail(ExtensionRow(item: item, settings: host.settings), chrome: chrome, host: host))
        case .group(let group)?:
            detail.setContent(groupDetail(group, chrome: chrome, host: host))
        case nil:
            detail.setContent([chrome.wrappingLabel("Select a command or a group to see its settings.")])
        }
    }

    private func itemDetail(_ row: ExtensionRow, chrome: SettingsChrome, host: SettingsHost) -> [NSView] {
        let item = row.item
        var views: [NSView] = [DetailHeaderView(
            icon: host.icons.image(for: item.icon, size: 32),
            title: item.title,
            type: row.typeLabel,
            chrome: chrome
        )]
        // The facts (`.detail-facts`): subtitle and id in SF Mono 11, 4 pt apart.
        let facts = NSStackView()
        facts.orientation = .vertical
        facts.alignment = .leading
        facts.spacing = 4
        if !item.subtitle.isEmpty {
            let subtitle = chrome.wrappingLabel(item.subtitle, font: ChromeFont.monoSmall)
            facts.addArrangedSubview(subtitle)
            subtitle.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        }
        let idLabel = chrome.wrappingLabel(item.id.rawValue, font: ChromeFont.monoSmall)
        idLabel.isSelectable = true
        idLabel.toolTip = "The id settings.json uses for this command"
        facts.addArrangedSubview(idLabel)
        idLabel.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        views.append(facts)

        let (section, body) = chrome.sectionCard(title: "Command")
        let alias = chrome.textField(row.alias ?? "", placeholder: "add alias", width: Self.detailControlWidth)
        alias.delegate = self
        detailAliasField = alias.field
        let hotkey = HotkeyButton(
            keycaps: row.hotkey.map(KeyboardLayout.caps(for:)) ?? [],
            theme: host.theme,
            style: .standard,
            target: self,
            action: #selector(detailRecordHotkey)
        )
        chrome.addRows([
            chrome.detailRow(label: "Alias", control: alias, toolTip: "Typed in Root Search, it puts this command first."),
            chrome.detailRow(label: "Hotkey", control: hotkey),
            chrome.detailRow(
                label: "Show in Root Search",
                control: chrome.switchControl(isOn: row.isEnabled, accessibilityLabel: "Show in Root Search", target: self, action: #selector(detailEnabledChanged(_:))),
                toolTip: "Hidden commands still run from their hotkey."
            ),
            chrome.detailRow(
                label: "Favorite",
                control: chrome.switchControl(isOn: row.isFavorite, accessibilityLabel: "Favorite", target: self, action: #selector(detailFavoriteChanged(_:)))
            ),
            chrome.detailRow(
                label: "Fallback command",
                control: chrome.switchControl(isOn: row.isFallback, accessibilityLabel: "Fallback command", target: self, action: #selector(detailFallbackChanged(_:))),
                toolTip: "Offered below the results of any search."
            ),
        ], to: body)
        views.append(section)

        if item.kind == .quicklink, let quicklink = host.settings.quicklinks.first(where: { $0.id == item.id.key }) {
            let (linkSection, linkBody) = chrome.sectionCard(title: "Quicklink")
            let form = QuicklinkFormView(fields: QuicklinkFields(quicklink), apps: Self.apps(in: host.items), chrome: chrome)
            quicklinkForm = form
            chrome.addRows(form.rows, to: linkBody)
            chrome.addRows([chrome.detailContent(chrome.hstack([
                chrome.button("Save", kind: .ink, target: self, action: #selector(saveQuicklinkClicked)),
                chrome.button("Delete Quicklink", kind: .danger, target: self, action: #selector(deleteQuicklinkClicked)),
            ]), fill: false)], to: linkBody)
            views.append(linkSection)
        }
        return views
    }

    private func groupDetail(_ group: ExtensionGroup, chrome: SettingsChrome, host: SettingsHost) -> [NSView] {
        var views: [NSView] = [chrome.tabHeader(title: group.title, subtitle: Self.groupDescription(group), titleFont: ChromeFont.headline)]
        switch group {
        case .applications, .scriptCommands:
            let isApps = group == .applications
            let (section, body) = chrome.sectionCard(
                title: isApps ? "Application folders" : "Script folders",
                subtitle: isApps
                    ? "Searched besides /Applications, /System/Applications, ~/Applications and /System/Library/CoreServices/Applications."
                    : "Raycast-format script commands in these folders and one level of subfolders; changes reload on their own."
            )
            let folders = Self.directories(group, in: host.settings)
            if folders.isEmpty {
                chrome.addRows([chrome.detailContent(chrome.wrappingLabel(isApps ? "No extra folders." : "No script folders yet."))], to: body)
            } else {
                chrome.addRows(folders.enumerated().map { index, path in
                    let remove = chrome.iconButton(symbol: "xmark", label: "Remove \(path)", target: self, action: #selector(removeFolderClicked(_:)))
                    remove.tag = index
                    return chrome.detailContent(chrome.hstack([chrome.lineLabel(path, font: ChromeFont.mono), remove]))
                }, to: body)
            }
            chrome.addRows([chrome.detailContent(chrome.button("Add Folder…", target: self, action: #selector(addFolderClicked)), fill: false)], to: body)
            views.append(section)
        case .quicklinks:
            let (section, body) = chrome.sectionCard(
                title: "Create quicklink",
                subtitle: "Placeholders: {argument}, {argument name=\"query\"}, {clipboard}, {date}, {time}, {uuid}."
            )
            let form = QuicklinkFormView(fields: QuicklinkFields(), apps: Self.apps(in: host.items), chrome: chrome)
            quicklinkForm = form
            chrome.addRows(form.rows, to: body)
            chrome.addRows([chrome.detailContent(chrome.button("Create Quicklink", kind: .ink, target: self, action: #selector(createQuicklinkClicked)), fill: false)], to: body)
            views.append(section)
        case .windowManagement:
            let settings = host.settings.windowManagement
            var gaps = Self.gapChoices
            if !gaps.contains(where: { $0.0 == settings.gap }) {
                gaps.append((settings.gap, "\(settings.gap) points"))
            }
            gapValues = gaps.map(\.0)
            let (section, body) = chrome.sectionCard(title: "Window Management")
            chrome.addRows([
                chrome.detailRow(
                    label: "Gap",
                    control: chrome.popup(titles: gaps.map(\.1), selected: gaps.firstIndex { $0.0 == settings.gap }, width: Self.detailControlWidth, target: self, action: #selector(gapChanged(_:))),
                    toolTip: "Space between windows and the display edges."
                ),
                chrome.detailRow(
                    label: "Cycling",
                    control: chrome.popup(
                        titles: Self.halvesChoices.map(\.1),
                        selected: Self.halvesChoices.firstIndex { $0.0 == settings.halves },
                        width: Self.detailControlWidth,
                        target: self,
                        action: #selector(halvesChanged(_:))
                    ),
                    toolTip: "What Left Half or Right Half does when the window already is that half."
                ),
            ], to: body)
            views.append(section)
        case .sopranoCast, .system, .systemSettings:
            break
        }
        return views
    }

    private static func groupDescription(_ group: ExtensionGroup) -> String {
        switch group {
        case .applications: "Every app Soprano Cast finds. An app's hotkey brings it to the front, and hides it when it already is."
        case .quicklinks: "Links, files and folders that open with what you type in Root Search."
        case .scriptCommands: "Raycast-format script commands from your script folders."
        case .sopranoCast: "Soprano Cast's own commands: these settings, reloading script folders, web search and Quit."
        case .system: "Lock, sleep, restart, shut down, log out, the Trash, ejecting, the appearance and Finder's hidden files."
        case .systemSettings: "Every System Settings pane, found by name in Root Search; it opens straight to that pane in System Settings."
        case .windowManagement: "Move and resize the frontmost window. Needs Accessibility."
        }
    }

    /// The apps a quicklink can open with: (title, bundle id or path), sorted by title.
    private static func apps(in items: [CastItem]) -> [(String, String)] {
        items.filter { $0.kind == .application }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { ($0.title, $0.id.key) }
    }

    // MARK: - Layout

    private func buildLayout() {
        for view in [topBar, header, scrollView, rule, detail] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for view in [titleLabel, countLabel, filterField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(view)
        }
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filterField.delegate = self
        filterField.field.setAccessibilityLabel("Search commands")

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            if column == .name {
                tableColumn.minWidth = 120
                tableColumn.resizingMask = .autoresizingMask
            } else {
                tableColumn.minWidth = column.width
                tableColumn.maxWidth = column.width
                tableColumn.resizingMask = []
            }
            table.addTableColumn(tableColumn)
        }
        table.headerView = nil
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.style = .plain
        table.floatsGroupRows = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Commands")
        scrollView.documentView = table
        scrollView.drawsBackground = false
        // The scroll thumb stays visible, like the mockup's table: a legacy (always shown)
        // scroller that draws only a `scrollbarThumb` thumb on no track.
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScroller = ThumbScroller()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        // Views draw past their bounds unless told otherwise (macOS 14); the floating
        // group row and the header must stay inside the table's area.
        scrollView.clipsToBounds = true
        header.clipsToBounds = true
        header.table = table
        header.columns = Column.allCases.map(\.title)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: rule.leadingAnchor),
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: Self.topBarHeight),

            // One 52 bar: the screen title and its baseline-aligned count left, search right.
            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: Chrome.Space.panel),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            countLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            filterField.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -Chrome.Space.panel),
            filterField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            filterField.widthAnchor.constraint(equalToConstant: 260),
            filterField.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 12),

            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: rule.leadingAnchor),
            header.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: ExtensionsHeaderView.height),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rule.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.trailingAnchor.constraint(equalTo: detail.leadingAnchor),

            detail.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.topAnchor.constraint(equalTo: topAnchor),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor),
            detail.widthAnchor.constraint(equalToConstant: Self.detailWidth),
        ])
    }

    private func applyTheme(_ theme: AppTheme) {
        let colors = theme.colors
        topBar.color = colors.bgBase
        rule.color = colors.borderStrong
        titleLabel.setChromeText("Extensions", font: ChromeFont.screen, color: colors.textPrimary, tracking: -0.2)
        filterField.apply(theme: theme)
        header.colors = colors
        (scrollView.verticalScroller as? ThumbScroller)?.thumbColor = colors.scrollbarThumb
    }
}

/// A vertical scroller that draws a rounded `scrollbarThumb` thumb and no track.
@MainActor
final class ThumbScroller: NSScroller {
    var thumbColor = NSColor.clear {
        didSet { needsDisplay = true }
    }

    override class var isCompatibleWithOverlayScrollers: Bool { false }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob).insetBy(dx: 4, dy: 2)
        guard knob.height > 0 else { return }
        thumbColor.setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
    }
}

// MARK: - Table pieces

/// The column titles above the table (eyebrows, muted) over a hairline, placed where the
/// table's columns are.
@MainActor
final class ExtensionsHeaderView: FlippedView {
    static let height: CGFloat = 26

    weak var table: NSTableView?
    var columns: [String] = []
    var colors: ThemeColors? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let colors, let table else { return }
        colors.bgBase.setFill()
        bounds.fill()
        for (index, title) in columns.enumerated() where index < table.numberOfColumns {
            let rect = convert(table.rect(ofColumn: index), from: table)
            let text = ChromeText.eyebrow(title, color: colors.textMuted)
            let size = text.size()
            let x: CGFloat = switch index {
            case 0: rect.minX + ExtensionsSettingsPane.tableLeading
            case columns.count - 1: rect.midX - size.width / 2
            default: rect.minX + ExtensionsSettingsPane.columnGap
            }
            text.draw(at: NSPoint(x: x, y: floor((bounds.height - size.height) / 2)))
        }
        colors.borderSubtle.setFill()
        NSRect(x: 0, y: bounds.height - Chrome.hairline, width: bounds.width, height: Chrome.hairline).fill()
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}

/// Rows on `bgBase`. The selected one is the focused pill with the pencil tick while the
/// table holds the keyboard, the muted pill otherwise; a hovered row gets the hover pill;
/// group rows carry a hairline under them.
@MainActor
final class ExtensionsRowView: NSTableRowView {
    var colors: ThemeColors?
    /// The pointer is over this command row (`ExtensionsTableView.hoveredRow`).
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
        }
    }

    /// The table holds the keyboard: the selection is the focused pill with the pencil
    /// tick; otherwise the muted pill without it.
    var isTableFocused: Bool {
        guard let table = superview as? NSTableView else { return false }
        return table.window?.firstResponder === table
    }

    /// The pill this row draws, for tests.
    var pillStyle: ChromeSelectionPill.Style {
        if isGroupRowStyle { return .none }
        if isSelected { return isTableFocused ? .selected : .selectedUnfocused }
        return isHovered ? .hover : .none
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let colors else { return super.drawBackground(in: dirtyRect) }
        colors.bgBase.setFill()
        bounds.fill()
        if isGroupRowStyle {
            colors.borderSubtle.setFill()
            NSRect(x: 0, y: bounds.height - Chrome.hairline, width: bounds.width, height: Chrome.hairline).fill()
        } else if !isSelected, isHovered {
            ChromeSelectionPill.draw(.hover, in: bounds, colors: colors, inset: Chrome.pillInset)
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard let colors else { return super.drawSelection(in: dirtyRect) }
        ChromeSelectionPill.draw(pillStyle, in: bounds, colors: colors, inset: Chrome.pillInset)
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

/// The commands table: redraws its rows' pills when it gains or loses the keyboard, and
/// tracks the row under the pointer for the hover pill (tracking works while Soprano Cast
/// is not the active app).
@MainActor
final class ExtensionsTableView: NSTableView {
    private(set) var hoveredRow = -1
    private var hoverArea: NSTrackingArea?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        redrawRows()
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        redrawRows()
        return resigned
    }

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

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredRow(-1)
    }

    /// Moves the hover pill to `row` (-1: none).
    func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        hoveredRow = row
        enumerateAvailableRowViews { view, index in
            (view as? ExtensionsRowView)?.isHovered = index == row
        }
    }

    private func redrawRows() {
        enumerateAvailableRowViews { view, _ in view.needsDisplay = true }
    }
}

/// A group row: a 12 pt chevron, the group title (SF 12 Semibold) and its command count.
@MainActor
final class GroupCellView: NSTableCellView {
    private static let chevronSize: CGFloat = 16

    init(section: ExtensionSection, collapsed: Bool, chrome: SettingsChrome, target: AnyObject, toggle: Selector, tag: Int) {
        super.init(frame: .zero)
        let chevron = chrome.iconButton(
            symbol: collapsed ? "chevron.right" : "chevron.down",
            label: collapsed ? "Expand \(section.group.title)" : "Collapse \(section.group.title)",
            pointSize: 12,
            size: Self.chevronSize,
            target: target,
            action: toggle
        )
        chevron.tag = tag
        let title = chrome.lineLabel(section.group.title, font: ChromeFont.sans(size: 12, weight: .semibold))
        let count = chrome.lineLabel("\(section.rows.count)", color: chrome.colors.textMuted, font: ChromeFont.sans(size: 12, tabular: true))
        let stack = chrome.hstack([chevron, title, count], spacing: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            // The 12 pt glyph starts at the table's 16 pt leading padding.
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ExtensionsSettingsPane.tableLeading - (Self.chevronSize - 12) / 2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - Detail pieces

/// The detail pane's title (`.detail-head`): a 32 pt icon beside the New York 17 title and
/// the meta type, centered on it.
@MainActor
final class DetailHeaderView: NSView {
    init(icon: NSImage, title: String, type: String, chrome: SettingsChrome) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let titleLabel = chrome.wrappingLabel(title, color: chrome.colors.textPrimary, font: ChromeFont.headline)
        let typeLabel = chrome.lineLabel(type, color: chrome.colors.textMuted, font: ChromeFont.meta)
        let text = NSStackView(views: [titleLabel, typeLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for view in [iconView, text] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: trailingAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            titleLabel.widthAnchor.constraint(equalTo: text.widthAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: text.bottomAnchor),
        ])
        let hug = heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .defaultLow
        hug.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Name, link, open-with app and icon of a quicklink, as card rows.
@MainActor
final class QuicklinkFormView {
    let rows: [NSView]
    private let name: SettingsField
    private let link: SettingsField
    private let openWith: NSPopUpButton
    private let icon: SettingsField
    /// The `openWith` values behind the pop-up's items ("" = the default app).
    private let openWithValues: [String]

    init(fields: QuicklinkFields, apps: [(String, String)], chrome: SettingsChrome) {
        let width = ExtensionsSettingsPane.detailControlWidth
        name = chrome.textField(fields.name, placeholder: "GitHub Repo", width: width)
        link = chrome.textField(fields.link, placeholder: "https://github.com/{argument}", width: width)
        icon = chrome.textField(fields.icon, placeholder: "emoji or image path", width: width)
        var titles = ["Default app"] + apps.map(\.0)
        var values = [""] + apps.map(\.1)
        let current = fields.openWith.trimmingCharacters(in: .whitespaces)
        var selected = 0
        if !current.isEmpty {
            if let index = values.firstIndex(of: current) ?? titles.firstIndex(where: { $0 == current || "\($0).app" == current }) {
                selected = index
            } else {
                titles.append(current)
                values.append(current)
                selected = titles.count - 1
            }
        }
        openWithValues = values
        let popup = chrome.popup(titles: titles, selected: selected, width: width, target: nil, action: nil)
        openWith = popup
        rows = [
            chrome.detailRow(label: "Name", control: name),
            chrome.detailRow(label: "Link", control: link, toolTip: "A URL, a file or folder path (~ allowed) or a deeplink."),
            chrome.detailRow(label: "Open with", control: popup),
            chrome.detailRow(label: "Icon", control: icon),
        ]
    }

    var fields: QuicklinkFields {
        let index = openWith.indexOfSelectedItem
        return QuicklinkFields(
            name: name.stringValue,
            link: link.stringValue,
            openWith: openWithValues.indices.contains(index) ? openWithValues[index] : "",
            icon: icon.stringValue
        )
    }
}

private extension SettingsChrome {
    /// A form row of the detail pane (`.ext-detail .form-row`): padding 6/12, min 40.
    func detailRow(label: String, control: NSView, toolTip: String? = nil) -> NSView {
        row(label: label, control: control, toolTip: toolTip, minHeight: Self.detailRowHeight, padding: Self.detailRowPadding)
    }

    /// Any view as a detail card row.
    func detailContent(_ view: NSView, fill: Bool = true) -> NSView {
        content(view, fill: fill, padding: Self.detailRowPadding)
    }
}
