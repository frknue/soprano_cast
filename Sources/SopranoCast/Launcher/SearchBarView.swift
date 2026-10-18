import AppKit
import SopranoCastCore

/// The search bar: the query field (body 18) with the selected item's argument fields
/// inline after its text, and a `borderSubtle` hairline below. User edits report the whole
/// text through `onQueryChange` / `onArgumentChange`; model updates never echo back.
final class SearchBarView: LauncherFlippedView, NSTextFieldDelegate {
    static let horizontalInset: CGFloat = 16
    static let queryFontSize: CGFloat = 18
    /// Space between the query text and the first argument field.
    static let queryArgumentGap: CGFloat = 12
    static let argumentGap: CGFloat = 8
    static let minimumQueryWidth: CGFloat = 40

    let queryField = LauncherText.inputField()
    /// The argument fields in order; a box is replaced only when its kind changes.
    private(set) var argumentBoxes: [ArgumentBoxView] = []
    var onQueryChange: ((String) -> Void)?
    var onArgumentChange: ((Int, String) -> Void)?

    private let rule = RetroRuleView(axis: .horizontal, style: .single)
    private var colors = AppTheme.missionControl.colors
    private var placeholder = ""

    init() {
        super.init(frame: .zero)
        queryField.font = RetroFont.body(Self.queryFontSize)
        queryField.delegate = self
        queryField.setAccessibilityLabel("Search")
        rule.translatesAutoresizingMaskIntoConstraints = true
        addSubview(queryField)
        addSubview(rule)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        query: String,
        placeholder: String,
        arguments: [ArgumentFieldViewModel],
        focus: LauncherFocus,
        colors: ThemeColors
    ) {
        self.colors = colors
        self.placeholder = placeholder
        queryField.textColor = colors.textPrimary
        queryField.placeholderAttributedString = LauncherText.plain(
            placeholder, font: RetroFont.body(Self.queryFontSize), color: colors.textMuted
        )
        LauncherText.sync(queryField, to: query)
        ensureBoxes(for: arguments)
        for (index, box) in argumentBoxes.enumerated() {
            box.configure(arguments[index], focused: focus == .argument(index), colors: colors)
        }
        rule.color = colors.borderSubtle
        layoutContents()
    }

    private func ensureBoxes(for arguments: [ArgumentFieldViewModel]) {
        while argumentBoxes.count > arguments.count {
            argumentBoxes.removeLast().removeFromSuperview()
        }
        for (index, argument) in arguments.enumerated() {
            let kind = ArgumentBoxView.Kind(argument)
            if index < argumentBoxes.count {
                guard argumentBoxes[index].kind != kind else { continue }
                argumentBoxes[index].removeFromSuperview()
                argumentBoxes[index] = makeBox(kind: kind, index: index)
            } else {
                argumentBoxes.append(makeBox(kind: kind, index: index))
            }
        }
    }

    private func makeBox(kind: ArgumentBoxView.Kind, index: Int) -> ArgumentBoxView {
        let box = ArgumentBoxView(kind: kind)
        box.onChange = { [weak self] value in self?.onArgumentChange?(index, value) }
        addSubview(box)
        return box
    }

    /// Without arguments the query field spans the bar; with them it is as wide as its text
    /// (or placeholder) so the argument fields sit right after it, like Raycast's.
    func layoutContents() {
        let bandHeight = bounds.height - Retro.hairline
        let centerY = bandHeight / 2
        let font = RetroFont.body(Self.queryFontSize)
        let fieldHeight = LauncherText.lineHeight(font) + 2
        let maxX = bounds.width - Self.horizontalInset
        var queryWidth = max(0, maxX - Self.horizontalInset)
        if !argumentBoxes.isEmpty {
            let count = CGFloat(argumentBoxes.count)
            let argumentsWidth = count * ArgumentBoxView.width + (count - 1) * Self.argumentGap
            let shown = queryField.stringValue.isEmpty ? placeholder : queryField.stringValue
            // A few points beyond the text leave room for the caret.
            let textWidth = LauncherText.width(of: LauncherText.plain(shown, font: font, color: colors.textPrimary)) + 4
            let room = maxX - Self.horizontalInset - Self.queryArgumentGap - argumentsWidth
            queryWidth = min(max(textWidth, Self.minimumQueryWidth), max(Self.minimumQueryWidth, room))
        }
        queryField.frame = CGRect(
            x: Self.horizontalInset,
            y: (centerY - fieldHeight / 2).rounded(),
            width: queryWidth,
            height: fieldHeight
        )
        var x = queryField.frame.maxX + Self.queryArgumentGap
        for box in argumentBoxes {
            box.frame = CGRect(
                x: x,
                y: (centerY - ArgumentBoxView.height / 2).rounded(),
                width: ArgumentBoxView.width,
                height: ArgumentBoxView.height
            )
            box.layoutContents()
            x += ArgumentBoxView.width + Self.argumentGap
        }
        rule.frame = CGRect(x: 0, y: bounds.height - Retro.hairline, width: bounds.width, height: Retro.hairline)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === queryField else { return }
        if !argumentBoxes.isEmpty {
            layoutContents()
        }
        onQueryChange?(queryField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        LauncherText.swallows(commandSelector)
    }
}

// MARK: - Argument field

/// One argument: a bordered `bgRaised` box (framed in `accent` while focused) holding a
/// body-14 text field, a secure field, or a pop-up menu for a dropdown.
final class ArgumentBoxView: LauncherFlippedView, NSTextFieldDelegate {
    static let width: CGFloat = 150
    static let height: CGFloat = 30
    static let horizontalInset: CGFloat = 8
    static let fontSize: CGFloat = 14

    enum Kind: Equatable {
        case text
        case secure
        /// Option titles.
        case dropdown([String])

        init(_ argument: ArgumentFieldViewModel) {
            if let options = argument.options {
                self = .dropdown(options)
            } else {
                self = argument.isSecure ? .secure : .text
            }
        }
    }

    let kind: Kind
    /// The view that takes keyboard focus: the text field or the pop-up button.
    let control: NSControl
    /// The user typed or picked a value (a dropdown reports the option title; clearing an
    /// optional dropdown reports "").
    var onChange: ((String) -> Void)?

    private var options: [String] = []
    private var placeholder = ""
    private var isOptional = false
    private var colors = AppTheme.missionControl.colors

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .text, .secure:
            let field = LauncherText.inputField(secure: kind == .secure)
            field.font = RetroFont.body(Self.fontSize)
            control = field
        case .dropdown:
            control = ArgumentPopUpButton()
        }
        super.init(frame: .zero)
        if let field = control as? NSTextField {
            field.delegate = self
        } else {
            control.target = self
            control.action = #selector(popUpChanged(_:))
        }
        addSubview(control)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ argument: ArgumentFieldViewModel, focused: Bool, colors: ThemeColors) {
        self.colors = colors
        layer?.backgroundColor = colors.bgRaised.cgColor
        layer?.borderColor = (focused ? colors.accent : colors.borderSubtle).cgColor
        layer?.borderWidth = Retro.hairline
        layer?.cornerRadius = Retro.cornerRadius
        control.setAccessibilityLabel(argument.placeholder)
        // Optional arguments read quieter, as in Raycast.
        let placeholderColor = argument.isOptional ? colors.textMuted.withAlphaComponent(0.6) : colors.textMuted
        if let field = control as? NSTextField {
            field.textColor = colors.textPrimary
            field.placeholderAttributedString = LauncherText.plain(
                argument.placeholder, font: RetroFont.body(Self.fontSize), color: placeholderColor
            )
            LauncherText.sync(field, to: argument.value)
            if focused {
                (field.currentEditor() as? NSTextView)?.insertionPointColor = colors.accent
            }
        } else if let popUp = control as? NSPopUpButton {
            configurePopUp(popUp, argument: argument, placeholderColor: placeholderColor)
        }
    }

    /// Item 0 is the placeholder: shown while no option matches the value, and offered in
    /// the menu only for an optional argument (picking it clears the value).
    private func configurePopUp(_ popUp: NSPopUpButton, argument: ArgumentFieldViewModel, placeholderColor: NSColor) {
        let options = argument.options ?? []
        let font = RetroFont.body(Self.fontSize)
        if options != self.options || argument.placeholder != placeholder || argument.isOptional != isOptional {
            self.options = options
            placeholder = argument.placeholder
            isOptional = argument.isOptional
            popUp.removeAllItems()
            // Through the menu: `addItems(withTitles:)` drops duplicate titles, which would
            // shift every index after them.
            for title in [argument.placeholder] + options {
                popUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
            }
        }
        for (index, item) in popUp.itemArray.enumerated() {
            let color = index == 0 ? placeholderColor : colors.textPrimary
            item.attributedTitle = LauncherText.plain(item.title, font: font, color: color)
        }
        popUp.itemArray.first?.isHidden = !argument.isOptional
        let selected = options.firstIndex(of: argument.value).map { $0 + 1 } ?? 0
        if popUp.indexOfSelectedItem != selected {
            popUp.selectItem(at: selected)
        }
    }

    func layoutContents() {
        if control is NSTextField {
            let height = LauncherText.lineHeight(RetroFont.body(Self.fontSize)) + 2
            control.frame = CGRect(
                x: Self.horizontalInset,
                y: ((bounds.height - height) / 2).rounded(),
                width: max(0, bounds.width - Self.horizontalInset * 2),
                height: height
            )
        } else {
            control.frame = bounds.insetBy(dx: 2, dy: 2)
        }
    }

    @objc private func popUpChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        if options.indices.contains(index) {
            onChange?(options[index])
        } else if isOptional {
            onChange?("")
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let field = control as? NSTextField else { return }
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        LauncherText.swallows(commandSelector)
    }
}

/// A borderless pop-up button that can hold keyboard focus (Tab cycles onto it) and opens
/// its menu on Space.
final class ArgumentPopUpButton: NSPopUpButton {
    init() {
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = true
        isBordered = false
        font = RetroFont.body(ArgumentBoxView.fontSize)
        menu?.appearance = NSAppearance(named: .darkAqua)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == NamedKey.space.keyCodes[0] {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
