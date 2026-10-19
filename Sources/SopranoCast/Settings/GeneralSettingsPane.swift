import AppKit
import SopranoCastCore

/// General: the settings.json card, Soprano Cast's own settings (login, hotkey, menu bar,
/// theme) and the ordered Favorites and Fallback Commands lists.
@MainActor
final class GeneralSettingsPane: NSView, SettingsPane {
    weak var host: SettingsHost?
    private let scroll = SettingsScrollColumn()
    /// The ids behind the list rows' buttons (tags are indices).
    private var listedFavorites: [ItemID] = []
    private var listedFallbacks: [ItemID] = []

    init() {
        super.init(frame: .zero)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func reload() {
        guard let host else { return }
        let chrome = SettingsChrome(theme: host.theme)
        listedFavorites = host.settings.favorites
        listedFallbacks = host.settings.fallbacks
        scroll.setContent([
            chrome.tabHeader(
                title: "General",
                subtitle: "Every setting in this window is stored in \(host.settingsPath); edits made there show up here as soon as the file is saved."
            ),
            fileCard(chrome, host),
            castCard(chrome, host),
            listCard(
                chrome,
                host,
                title: "favorites",
                subtitle: "Root Search shows these first while the search is empty, in this order. Add more with ⌘F in Root Search or Favorite in Extensions.",
                ids: listedFavorites,
                empty: "No favorites yet.",
                up: #selector(moveFavoriteUp(_:)),
                down: #selector(moveFavoriteDown(_:)),
                remove: #selector(removeFavorite(_:))
            ),
            listCard(
                chrome,
                host,
                title: "fallback commands",
                subtitle: "Listed below the results of any search (“Use “x” with …”), in this order. Add more with Fallback command in Extensions.",
                ids: listedFallbacks,
                empty: "No fallback commands.",
                up: #selector(moveFallbackUp(_:)),
                down: #selector(moveFallbackDown(_:)),
                remove: #selector(removeFallback(_:))
            ),
        ])
    }

    // MARK: - Cards

    private func fileCard(_ chrome: SettingsChrome, _ host: SettingsHost) -> NSView {
        let (section, body) = chrome.sectionCard(
            title: "settings.json",
            subtitle: "This window edits \(host.settingsPath). Hand edits apply as soon as you save; comments and key order are kept."
        )
        for issue in host.issues {
            let row = chrome.issueRow(issue)
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -2 * SettingsChrome.cardInset).isActive = true
        }
        let buttons = chrome.hstack([
            chrome.button("Open settings.json", target: self, action: #selector(openFile)),
            chrome.button("Reveal in Finder", target: self, action: #selector(revealFile)),
        ])
        body.addArrangedSubview(buttons)
        return section
    }

    private func castCard(_ chrome: SettingsChrome, _ host: SettingsHost) -> NSView {
        let settings = host.settings
        let (section, body) = chrome.sectionCard(title: "soprano cast")
        let themes = AppTheme.allThemes
        let themeIndex = settings.theme == "soprano" ? 0 : themes.firstIndex { $0.id == settings.theme }.map { $0 + 1 }
        let hotkey = HotkeyButton(
            keycaps: settings.launcher.hotkey.map(KeyboardLayout.keycaps(for:)) ?? [],
            theme: host.theme,
            target: self,
            action: #selector(recordLauncherHotkey)
        )
        chrome.addRows([
            chrome.row(
                label: "Launch at login",
                control: chrome.checkbox(isOn: settings.app.startAtLogin, accessibilityLabel: "Launch at login", target: self, action: #selector(startAtLoginChanged(_:)))
            ),
            chrome.row(
                label: "Soprano Cast hotkey",
                control: hotkey,
                toolTip: "Opens and closes Soprano Cast. Record ⌫ for no hotkey."
            ),
            chrome.row(
                label: "Show in menu bar",
                control: chrome.checkbox(isOn: settings.app.showMenuBarIcon, accessibilityLabel: "Show in menu bar", target: self, action: #selector(menuBarIconChanged(_:))),
                toolTip: "Without the icon, open these settings with ⌘, in Soprano Cast."
            ),
            chrome.row(
                label: "Theme",
                control: chrome.popup(
                    titles: ["Follow Soprano"] + themes.map(\.name),
                    selected: themeIndex,
                    target: self,
                    action: #selector(themeChanged(_:))
                )
            ),
        ], to: body)
        return section
    }

    private func listCard(
        _ chrome: SettingsChrome,
        _ host: SettingsHost,
        title: String,
        subtitle: String,
        ids: [ItemID],
        empty: String,
        up: Selector,
        down: Selector,
        remove: Selector
    ) -> NSView {
        let (section, body) = chrome.sectionCard(title: title, subtitle: subtitle)
        guard !ids.isEmpty else {
            let label = chrome.wrappingLabel(empty)
            body.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -2 * SettingsChrome.cardInset).isActive = true
            return section
        }
        let items = Dictionary(host.items.map { ($0.id, $0) }) { first, _ in first }
        let rows = ids.enumerated().map { index, id in
            ItemListRow(
                item: items[id],
                id: id,
                index: index,
                count: ids.count,
                chrome: chrome,
                icons: host.icons,
                target: self,
                up: up,
                down: down,
                remove: remove
            )
        }
        chrome.addRows(rows, to: body)
        return section
    }

    // MARK: - Actions

    @objc private func openFile() {
        host?.openSettingsFile()
    }

    @objc private func revealFile() {
        host?.revealSettingsFile()
    }

    @objc private func startAtLoginChanged(_ sender: NSButton) {
        host?.apply([.set(sender.state == .on, ["app", "startAtLogin"])])
    }

    @objc private func menuBarIconChanged(_ sender: NSButton) {
        host?.apply([.set(sender.state == .on, ["app", "showMenuBarIcon"])])
    }

    @objc private func recordLauncherHotkey() {
        host?.recordHotkey(for: .launcher, title: "Soprano Cast")
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        let themes = AppTheme.allThemes
        let id = index <= 0 ? "soprano" : themes[min(index - 1, themes.count - 1)].id
        host?.apply([.set(id, ["theme"])])
    }

    @objc private func moveFavoriteUp(_ sender: NSButton) {
        moveFavorite(at: sender.tag, by: -1)
    }

    @objc private func moveFavoriteDown(_ sender: NSButton) {
        moveFavorite(at: sender.tag, by: 1)
    }

    @objc private func removeFavorite(_ sender: NSButton) {
        guard let host, listedFavorites.indices.contains(sender.tag) else { return }
        host.apply([.set(host.settings.favoriteIDs(toggling: listedFavorites[sender.tag]), ["favorites"])])
    }

    @objc private func moveFallbackUp(_ sender: NSButton) {
        moveFallback(at: sender.tag, by: -1)
    }

    @objc private func moveFallbackDown(_ sender: NSButton) {
        moveFallback(at: sender.tag, by: 1)
    }

    @objc private func removeFallback(_ sender: NSButton) {
        guard let host, listedFallbacks.indices.contains(sender.tag) else { return }
        host.apply([.set(host.settings.fallbackIDs(toggling: listedFallbacks[sender.tag]), ["fallbacks"])])
    }

    private func moveFavorite(at index: Int, by offset: Int) {
        guard let host, listedFavorites.indices.contains(index),
              let favorites = host.settings.favoriteIDs(moving: listedFavorites[index], by: offset)
        else { return }
        host.apply([.set(favorites, ["favorites"])])
    }

    private func moveFallback(at index: Int, by offset: Int) {
        guard let host, listedFallbacks.indices.contains(index),
              let fallbacks = host.settings.fallbackIDs(moving: listedFallbacks[index], by: offset)
        else { return }
        host.apply([.set(fallbacks, ["fallbacks"])])
    }
}

/// One command in an ordered list: icon, title, type, and ↑ ↓ ✕ keys (tagged with its
/// index). An id without an item right now (an app since removed) shows the raw id.
@MainActor
final class ItemListRow: NSView {
    init(
        item: CastItem?,
        id: ItemID,
        index: Int,
        count: Int,
        chrome: SettingsChrome,
        icons: IconProviding,
        target: AnyObject,
        up: Selector?,
        down: Selector?,
        remove: Selector
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView()
        icon.image = item.map { icons.image(for: $0.icon, size: 16) }
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = chrome.lineLabel(item?.title ?? id.rawValue, color: item == nil ? chrome.colors.textMuted : nil)
        let type = chrome.lineLabel(item?.kind?.label ?? "not available", color: chrome.colors.textMuted, size: 11)
        var buttons: [NSView] = []
        if let up {
            let button = chrome.iconButton(symbol: "chevron.up", label: "Move up", target: target, action: up)
            button.tag = index
            button.isEnabled = index > 0
            buttons.append(button)
        }
        if let down {
            let button = chrome.iconButton(symbol: "chevron.down", label: "Move down", target: target, action: down)
            button.tag = index
            button.isEnabled = index < count - 1
            buttons.append(button)
        }
        let removeButton = chrome.iconButton(symbol: "xmark", label: "Remove", target: target, action: remove)
        removeButton.tag = index
        buttons.append(removeButton)
        let controls = chrome.hstack(buttons, spacing: 2)

        for view in [icon, title, type, controls] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsChrome.rowHeight),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            type.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            type.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            type.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -8),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
