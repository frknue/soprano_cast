import AppKit
import SopranoCastCore

/// A footer message the launcher shows for a few seconds.
struct LauncherToast: Equatable {
    var text: String
    var isError: Bool
}

/// Turns the launcher controller's state into the `LauncherViewModel` the presenter draws:
/// rows with their accessories, alias badges and hotkey keycaps, argument fields, the
/// footer, the overlay cards and the empty text.
@MainActor
enum LauncherModelBuilder {
    static let placeholder = "Search for apps and commands…"
    static let noResultsText = "No results"
    static let emptyQueryText = "Type to search apps and commands"
    static let recorderHint = "⌫ clear · ⎋ cancel · ↵ save"
    /// Row icons are drawn at this size (points).
    static let iconSize: CGFloat = 24

    /// - Parameters:
    ///   - arguments: the argument fields to show (the selected item's; none for fallback
    ///     and calculator rows).
    ///   - argumentValues: their values in `arguments` order (dropdowns: the option value).
    ///   - focus: the Root Search focus; an overlay overrides it.
    ///   - keycaps: how an item's hotkey is drawn; physical keys show what they type on the
    ///     current layout (tests pass a fixed one).
    static func model(
        theme: AppTheme,
        query: String,
        sections: [ResultSection],
        selectedIndex: Int?,
        arguments: [ArgumentSpec],
        argumentValues: [String],
        focus: LauncherFocus,
        toast: LauncherToast?,
        overlay: OverlayViewModel,
        settings: CastSettings,
        icon: (ItemIcon) -> NSImage,
        keycaps: (HotkeySpec) -> [String] = KeyboardLayout.keycaps(for:)
    ) -> LauncherViewModel {
        let rows = sections.flatMap(\.rows)
        let selected = selectedIndex.flatMap { rows.indices.contains($0) ? rows[$0].item : nil }
        let isEmpty = rows.isEmpty
        return LauncherViewModel(
            theme: theme,
            query: query,
            placeholder: placeholder,
            arguments: argumentFields(arguments, values: argumentValues),
            sections: sections.map { section in
                let fallbackQuery = section.kind == .fallbacks ? trimmed(query) : nil
                return SectionViewModel(
                    title: fallbackQuery.map(fallbacksTitle(query:)) ?? section.kind.title,
                    rows: section.rows.map {
                        row($0, settings: settings, fallbackQuery: fallbackQuery, icon: icon, keycaps: keycaps)
                    }
                )
            },
            selectedIndex: selected == nil ? nil : selectedIndex,
            footer: FooterViewModel(
                toast: toast?.text,
                toastIsError: toast?.isError ?? false,
                primaryTitle: selected.map { ItemActions.primary(for: $0).title },
                showsActions: selected != nil
            ),
            overlay: overlay,
            focus: resolvedFocus(focus, overlay: overlay, argumentCount: arguments.count),
            emptyText: isEmpty ? emptyText(query: query) : nil
        )
    }

    /// "No results" with a query, "Type to search apps and commands" without.
    static func emptyText(query: String) -> String {
        trimmed(query).isEmpty ? emptyQueryText : noResultsText
    }

    /// The fallbacks section's header: `use “<query>” with…`.
    static func fallbacksTitle(query: String) -> String {
        "use \(quoted(query)) with…"
    }

    /// - Parameter fallbackQuery: the trimmed query when the row is in the fallbacks
    ///   section; the row then shows it as its subtitle and its kind's label as accessory.
    static func row(
        _ ranked: RankedItem,
        settings: CastSettings,
        fallbackQuery: String? = nil,
        icon: (ItemIcon) -> NSImage,
        keycaps: (HotkeySpec) -> [String] = KeyboardLayout.keycaps(for:)
    ) -> RowViewModel {
        let item = ranked.item
        let subtitle: String
        let accessory: String
        if let fallbackQuery {
            subtitle = quoted(fallbackQuery)
            accessory = item.kind?.label ?? ""
        } else {
            subtitle = accessoryUsesSubtitle(item) ? "" : item.subtitle
            accessory = Self.accessory(for: item)
        }
        return RowViewModel(
            id: item.id,
            title: item.title,
            titleHighlights: ranked.titleRanges.compactMap { range in
                guard range.lowerBound >= item.title.startIndex, range.upperBound <= item.title.endIndex else { return nil }
                return NSRange(range, in: item.title)
            },
            subtitle: subtitle,
            icon: icon(item.icon),
            accessory: accessory,
            alias: settings.aliases[item.id],
            hotkeyKeys: settings.hotkeys[item.id].map(keycaps) ?? []
        )
    }

    private static func trimmed(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quoted(_ text: String) -> String {
        "“\(text)”"
    }

    /// The trailing label: the kind's label; the calculator's expression; a script's
    /// package name (its subtitle).
    static func accessory(for item: CastItem) -> String {
        switch item.kind {
        case .calculator?:
            return item.subtitle
        case .script? where !item.subtitle.isEmpty:
            return item.subtitle
        case let kind?:
            return kind.label
        case nil:
            return ""
        }
    }

    /// The calculator's and scripts' subtitles move to the accessory, so the row doesn't
    /// show them twice.
    private static func accessoryUsesSubtitle(_ item: CastItem) -> Bool {
        item.kind == .calculator || item.kind == .script
    }

    /// Dropdown fields carry the selected option's title as their value (the pop-up selects
    /// by title); `values` holds option values.
    static func argumentFields(_ specs: [ArgumentSpec], values: [String]) -> [ArgumentFieldViewModel] {
        specs.enumerated().map { index, spec in
            let value = values.indices.contains(index) ? values[index] : ""
            var options: [String]?
            var shown = value
            if case .dropdown(let choices) = spec.kind {
                options = choices.map(\.title)
                shown = choices.first { $0.value == value }?.title ?? value
            }
            return ArgumentFieldViewModel(
                placeholder: spec.placeholder.isEmpty ? spec.name : spec.placeholder,
                value: shown,
                isSecure: spec.kind == .password,
                options: options,
                isOptional: spec.isOptional
            )
        }
    }

    static func actionRows(_ actions: [ItemAction]) -> [ActionRowViewModel] {
        actions.map { action in
            ActionRowViewModel(
                title: action.title,
                keys: action.shortcut.map { HotkeySpec.combo($0).keycaps } ?? [],
                isDestructive: action.isDestructive
            )
        }
    }

    /// What the recorder card shows as keycaps.
    enum RecorderKeys: Equatable {
        /// A hotkey (the current one, or what was just recorded), drawn with `keycaps`.
        case spec(HotkeySpec)
        /// The recorder's own display strings while modifiers are held.
        case display([String])
    }

    static func recorder(
        itemTitle: String,
        keys: RecorderKeys,
        conflict: String?,
        countdown: Double?,
        keycaps: (HotkeySpec) -> [String] = KeyboardLayout.keycaps(for:)
    ) -> OverlayViewModel {
        let shown = switch keys {
        case .spec(let spec): keycaps(spec)
        case .display(let display): display
        }
        return .recorder(itemTitle: itemTitle, keys: shown, conflict: conflict, countdown: countdown, hint: recorderHint)
    }

    /// "Used by <title>" for the target already holding a recorded hotkey.
    static func conflictText(ownerTitle: String?) -> String? {
        ownerTitle.map { "Used by \($0)" }
    }

    /// Overlays with a text field focus it; the others take the keyboard without one.
    private static func resolvedFocus(_ focus: LauncherFocus, overlay: OverlayViewModel, argumentCount: Int) -> LauncherFocus {
        switch overlay {
        case .none:
            if case .argument(let index) = focus, index >= argumentCount { return .query }
            return focus
        case .actionPanel, .aliasEditor:
            return .overlay
        case .recorder, .output, .confirmation:
            return .none
        }
    }
}
