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

        var title: String { rawValue }
        var width: CGFloat {
            switch self {
            case .name: 220
            case .type: 120
            case .alias: 76
            case .hotkey: 108
            case .enabled: 56
            }
        }
    }

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
    private let filterField = NSTextField(string: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let header = ExtensionsHeaderView()
    private let scrollView = NSScrollView()
    private let table = NSTableView()
    private let rule = RetroRuleView(axis: .vertical, style: .single)
    private let detail = SettingsScrollColumn(maxWidth: 10_000)

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
        table.tile()
        if let row = selectedLineIndex {
            table.scrollRowToVisible(row)
        }
        scrollView.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
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
        countLabel.attributedStringValue = RetroText.display(
            "\(commands) \(commands == 1 ? "command" : "commands")",
            color: host.theme.colors.textMuted,
            alignment: .right
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
            let title = chrome.lineLabel(row.item.title, color: row.isEnabled ? colors.textPrimary : colors.textMuted, size: 13)
            let stack = chrome.hstack([icon, title], spacing: 8)
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            content = stack
        case .type:
            content = chrome.lineLabel(row.typeLabel, color: colors.textMuted)
        case .alias:
            let field = NSTextField(string: row.alias ?? "")
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = RetroFont.body(12)
            field.textColor = colors.accent
            field.isEditable = true
            field.delegate = self
            field.tag = index
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.placeholderAttributedString = NSAttributedString(
                string: isSelected ? "add alias" : "",
                attributes: [.font: RetroFont.body(12), .foregroundColor: colors.textMuted]
            )
            field.setAccessibilityLabel("Alias of \(row.item.title)")
            content = field
        case .hotkey:
            let button = HotkeyButton(
                keycaps: row.hotkey.map(KeyboardLayout.keycaps(for:)) ?? [],
                theme: chrome.theme,
                target: self,
                action: #selector(recordRowHotkey(_:))
            )
            button.tag = index
            button.placeholder = "record"
            button.showsPlaceholder = isSelected
            content = button
        case .enabled:
            let box = chrome.checkbox(isOn: row.isEnabled, accessibilityLabel: "Show \(row.item.title) in Root Search", target: self, action: #selector(enabledChanged(_:)))
            box.tag = index
            content = box
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        var constraints = [content.centerYAnchor.constraint(equalTo: container.centerYAnchor)]
        switch column {
        case .enabled:
            constraints.append(content.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        case .hotkey:
            constraints += [
                content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                content.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 4),
            ]
        default:
            constraints += [
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: column == .name ? 14 : 6),
                content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -6),
            ]
            if column == .alias {
                constraints.append(content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6))
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
        guard let field = notification.object as? NSTextField, field === filterField else { return }
        setFilter(field.stringValue)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field !== filterField else { return }
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

    @objc private func enabledChanged(_ sender: NSButton) {
        guard lines.indices.contains(sender.tag), case .item(let row) = lines[sender.tag] else { return }
        setEnabled(sender.state == .on, for: row.item.id)
    }

    @objc private func detailRecordHotkey() {
        guard case .item(let id)? = selection, let item = host?.items.first(where: { $0.id == id }) else { return }
        host?.recordHotkey(for: .item(id), title: item.title)
    }

    @objc private func detailEnabledChanged(_ sender: NSButton) {
        guard case .item(let id)? = selection else { return }
        setEnabled(sender.state == .on, for: id)
    }

    @objc private func detailFavoriteChanged(_ sender: NSButton) {
        guard case .item(let id)? = selection else { return }
        setFavorite(sender.state == .on, for: id)
    }

    @objc private func detailFallbackChanged(_ sender: NSButton) {
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
        if !item.subtitle.isEmpty {
            views.append(chrome.wrappingLabel(item.subtitle))
        }
        let idLabel = chrome.wrappingLabel(item.id.rawValue)
        idLabel.isSelectable = true
        idLabel.toolTip = "The id settings.json uses for this command"
        views.append(idLabel)

        let (section, body) = chrome.sectionCard(title: "command")
        let alias = chrome.textField(row.alias ?? "", placeholder: "add alias", width: 130)
        alias.delegate = self
        detailAliasField = alias
        let hotkey = HotkeyButton(
            keycaps: row.hotkey.map(KeyboardLayout.keycaps(for:)) ?? [],
            theme: host.theme,
            target: self,
            action: #selector(detailRecordHotkey)
        )
        chrome.addRows([
            chrome.row(label: "Alias", control: alias, toolTip: "Typed in Root Search, it puts this command first."),
            chrome.row(label: "Hotkey", control: hotkey),
            chrome.row(
                label: "Show in Root Search",
                control: chrome.checkbox(isOn: row.isEnabled, accessibilityLabel: "Show in Root Search", target: self, action: #selector(detailEnabledChanged(_:))),
                toolTip: "Hidden commands still run from their hotkey."
            ),
            chrome.row(
                label: "Favorite",
                control: chrome.checkbox(isOn: row.isFavorite, accessibilityLabel: "Favorite", target: self, action: #selector(detailFavoriteChanged(_:)))
            ),
            chrome.row(
                label: "Fallback command",
                control: chrome.checkbox(isOn: row.isFallback, accessibilityLabel: "Fallback command", target: self, action: #selector(detailFallbackChanged(_:))),
                toolTip: "Offered below the results of any search."
            ),
        ], to: body)
        views.append(section)

        if item.kind == .quicklink, let quicklink = host.settings.quicklinks.first(where: { $0.id == item.id.key }) {
            let (linkSection, linkBody) = chrome.sectionCard(title: "quicklink")
            let form = QuicklinkFormView(fields: QuicklinkFields(quicklink), apps: Self.apps(in: host.items), chrome: chrome)
            quicklinkForm = form
            chrome.addRows(form.rows, to: linkBody)
            linkBody.addArrangedSubview(chrome.hstack([
                chrome.button("Save", kind: .prominent, target: self, action: #selector(saveQuicklinkClicked)),
                DangerButton(title: "Delete Quicklink", theme: host.theme, target: self, action: #selector(deleteQuicklinkClicked)),
            ]))
            views.append(linkSection)
        }
        return views
    }

    private func groupDetail(_ group: ExtensionGroup, chrome: SettingsChrome, host: SettingsHost) -> [NSView] {
        var views: [NSView] = [chrome.tabHeader(title: group.title, subtitle: Self.groupDescription(group))]
        switch group {
        case .applications, .scriptCommands:
            let isApps = group == .applications
            let (section, body) = chrome.sectionCard(
                title: isApps ? "application folders" : "script folders",
                subtitle: isApps
                    ? "Searched besides /Applications, /System/Applications, ~/Applications and /System/Library/CoreServices/Applications."
                    : "Raycast-format script commands in these folders and one level of subfolders; changes reload on their own."
            )
            let folders = Self.directories(group, in: host.settings)
            if folders.isEmpty {
                let label = chrome.wrappingLabel(isApps ? "No extra folders." : "No script folders yet.")
                body.addArrangedSubview(label)
                label.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -2 * SettingsChrome.cardInset).isActive = true
            } else {
                chrome.addRows(folders.enumerated().map { index, path in
                    let remove = chrome.iconButton(symbol: "xmark", label: "Remove \(path)", target: self, action: #selector(removeFolderClicked(_:)))
                    remove.tag = index
                    return chrome.row(label: "", control: chrome.hstack([chrome.lineLabel(path), remove]))
                }, to: body)
            }
            body.addArrangedSubview(chrome.button("Add Folder…", target: self, action: #selector(addFolderClicked)))
            views.append(section)
        case .quicklinks:
            let (section, body) = chrome.sectionCard(
                title: "create quicklink",
                subtitle: "Placeholders: {argument}, {argument name=\"query\"}, {clipboard}, {date}, {time}, {uuid}."
            )
            let form = QuicklinkFormView(fields: QuicklinkFields(), apps: Self.apps(in: host.items), chrome: chrome)
            quicklinkForm = form
            chrome.addRows(form.rows, to: body)
            body.addArrangedSubview(chrome.button("Create Quicklink", kind: .prominent, target: self, action: #selector(createQuicklinkClicked)))
            views.append(section)
        case .windowManagement:
            let settings = host.settings.windowManagement
            var gaps = Self.gapChoices
            if !gaps.contains(where: { $0.0 == settings.gap }) {
                gaps.append((settings.gap, "\(settings.gap) points"))
            }
            gapValues = gaps.map(\.0)
            let (section, body) = chrome.sectionCard(title: "window management")
            chrome.addRows([
                chrome.row(
                    label: "Gap",
                    control: chrome.popup(titles: gaps.map(\.1), selected: gaps.firstIndex { $0.0 == settings.gap }, width: Self.detailControlWidth, target: self, action: #selector(gapChanged(_:))),
                    toolTip: "Space between windows and the display edges."
                ),
                chrome.row(
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
        case .sopranoCast, .system:
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
        for view in [filterField, countLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(view)
        }
        filterField.delegate = self
        filterField.isBordered = true
        filterField.focusRingType = .none
        filterField.drawsBackground = true
        filterField.wantsLayer = true
        filterField.layer?.borderWidth = Retro.hairline
        filterField.font = RetroFont.body(12)
        filterField.cell?.usesSingleLineMode = true
        filterField.setAccessibilityLabel("Search commands")

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
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
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

            filterField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            filterField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            filterField.widthAnchor.constraint(equalToConstant: 260),
            countLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: filterField.trailingAnchor, constant: 12),

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
            rule.widthAnchor.constraint(equalToConstant: Retro.hairline),
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
        filterField.backgroundColor = colors.bgRaised
        filterField.textColor = colors.textPrimary
        filterField.layer?.borderColor = colors.borderStrong.cgColor
        filterField.placeholderAttributedString = NSAttributedString(
            string: "search commands…",
            attributes: [.font: RetroFont.body(12), .foregroundColor: colors.textMuted]
        )
        header.colors = colors
    }
}

// MARK: - Table pieces

/// The column titles above the table (display 11, muted) over a hairline, placed where
/// the table's columns are.
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
            let text = RetroText.display(title, color: colors.textMuted)
            let size = text.size()
            let x: CGFloat = switch index {
            case 0: rect.minX + 14
            case columns.count - 1: rect.midX - size.width / 2
            case columns.count - 2: rect.maxX - 12 - size.width
            default: rect.minX + 6
            }
            text.draw(at: NSPoint(x: x, y: floor((bounds.height - size.height) / 2)))
        }
        colors.borderSubtle.setFill()
        NSRect(x: 0, y: bounds.height - Retro.hairline, width: bounds.width, height: Retro.hairline).fill()
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}

/// Rows: the selected one in `bgSelectedStrong` with a 2 pt `accent` rail (the launcher's
/// selection); group rows on `bgPanel`.
@MainActor
final class ExtensionsRowView: NSTableRowView {
    var colors: ThemeColors?

    override func drawBackground(in dirtyRect: NSRect) {
        guard let colors else { return super.drawBackground(in: dirtyRect) }
        (isGroupRowStyle ? colors.bgPanel : colors.bgBase).setFill()
        bounds.fill()
        if isGroupRowStyle {
            colors.borderSubtle.setFill()
            NSRect(x: 0, y: bounds.height - Retro.hairline, width: bounds.width, height: Retro.hairline).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard let colors else { return super.drawSelection(in: dirtyRect) }
        colors.bgSelectedStrong.setFill()
        bounds.fill()
        colors.accent.setFill()
        NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

/// A group row: disclosure chevron, the group title (display 11) and its command count.
@MainActor
final class GroupCellView: NSTableCellView {
    init(section: ExtensionSection, collapsed: Bool, chrome: SettingsChrome, target: AnyObject, toggle: Selector, tag: Int) {
        super.init(frame: .zero)
        let chevron = chrome.iconButton(
            symbol: collapsed ? "chevron.right" : "chevron.down",
            label: collapsed ? "Expand \(section.group.title)" : "Collapse \(section.group.title)",
            target: target,
            action: toggle
        )
        chevron.tag = tag
        let title = NSTextField(labelWithString: section.group.title)
        title.setRetroText(section.group.title, color: chrome.colors.textPrimary)
        let count = chrome.lineLabel("\(section.rows.count)", color: chrome.colors.textMuted, size: 11)
        let stack = chrome.hstack([chevron, title, count], spacing: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - Detail pieces

/// The detail pane's title: a 32 pt icon, the title (body 15) and the type (display 11).
@MainActor
final class DetailHeaderView: NSView {
    init(icon: NSImage, title: String, type: String, chrome: SettingsChrome) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let titleLabel = chrome.wrappingLabel(title, color: chrome.colors.textPrimary, size: 15)
        let typeLabel = NSTextField(labelWithString: type)
        typeLabel.setRetroText(type, color: chrome.colors.textMuted)
        for view in [iconView, titleLabel, typeLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            typeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            typeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            bottomAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: typeLabel.bottomAnchor),
        ])
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
    private let name: NSTextField
    private let link: NSTextField
    private let openWith: NSPopUpButton
    private let icon: NSTextField
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
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        popup.selectItem(at: selected)
        popup.font = RetroFont.body(12)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        openWith = popup
        rows = [
            chrome.row(label: "Name", control: name),
            chrome.row(label: "Link", control: link, toolTip: "A URL, a file or folder path (~ allowed) or a deeplink."),
            chrome.row(label: "Open with", control: popup),
            chrome.row(label: "Icon", control: icon),
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
