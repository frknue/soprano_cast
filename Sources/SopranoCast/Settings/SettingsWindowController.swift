import AppKit
import SopranoCastCore

/// What the settings window needs from the app; injectable for tests and the harness.
struct SettingsWindowEnvironment {
    var settings: @MainActor () -> CastSettings
    var issues: @MainActor () -> [ConfigIssue]
    /// settings.json's path as shown ("~/.config/soprano-cast/settings.json").
    var settingsPath: String
    var editSettings: @MainActor (SettingsEdit) throws -> Void
    /// Every item Root Search lists (the launcher's `allItems`).
    var items: @MainActor () -> [CastItem]
    var theme: @MainActor () -> AppTheme
    /// Runs `work` after `milliseconds` on the main actor; returns a cancel closure.
    var schedule: @MainActor (_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> (() -> Void)
    var openSettingsFile: @MainActor () -> Void
    var revealSettingsFile: @MainActor () -> Void
    /// Asks for a folder and calls back with its path ("~/…" inside the home folder).
    var chooseFolder: @MainActor (_ completion: @escaping @MainActor (String) -> Void) -> Void
}

/// The settings window's tabs (Raycast's, without the ones not copied).
enum SettingsTab: String, CaseIterable {
    case general
    case extensions
    case advanced

    var title: String {
        switch self {
        case .general: "General"
        case .extensions: "Extensions"
        case .advanced: "Advanced"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .extensions: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// What a tab pane reads and calls on the window.
@MainActor
protocol SettingsHost: AnyObject {
    var settings: CastSettings { get }
    var issues: [ConfigIssue] { get }
    var items: [CastItem] { get }
    var theme: AppTheme { get }
    var settingsPath: String { get }
    var icons: IconProviding { get }
    /// Writes the edits in order; a failure shows in the status line and stops the rest.
    /// True when all were written. The panes redraw afterwards.
    @discardableResult
    func apply(_ edits: [SettingsEdit]) -> Bool
    /// Opens the recorder card for the launcher's or an item's hotkey.
    func recordHotkey(for target: HotkeyTarget, title: String)
    /// A short message at the bottom of the sidebar (`danger` when an error).
    func showStatus(_ text: String, isError: Bool)
    func openSettingsFile()
    func revealSettingsFile()
    func chooseFolder(_ completion: @escaping @MainActor (String) -> Void)
}

/// One tab's content; redrawn from the host whenever settings, items or the theme change.
@MainActor
protocol SettingsPane: NSView {
    var host: SettingsHost? { get set }
    func reload()
}

/// The settings window (Raycast's Settings, in Soprano's chrome): a sidebar of tabs and the
/// tab's pane. Every control writes settings.json through `SettingsEdit`; the window keeps
/// no settings of its own and redraws when the file changes. Hotkeys are recorded in the
/// launcher's recorder card with the same `HotkeyRecordingSession`.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, SettingsHost {
    static let contentSize = NSSize(width: 1120, height: 700)
    static let minimumSize = NSSize(width: 1000, height: 560)
    static let sidebarWidth: CGFloat = 180
    static let statusMilliseconds = 4000

    private let environment: SettingsWindowEnvironment
    let icons: IconProviding
    private let hotkeys: HotkeyRegistering
    private let keyCode: (KeySpec) -> UInt16?

    private(set) var settings: CastSettings
    private(set) var issues: [ConfigIssue]
    private(set) var items: [CastItem]
    private(set) var theme: AppTheme
    var settingsPath: String { environment.settingsPath }

    private(set) var currentTab: SettingsTab = .general
    private let rootView = LayerView()
    private let sidebar = LayerView()
    private let sidebarRule = RetroRuleView(axis: .vertical, style: .single)
    private let tabStack = NSStackView()
    private var tabButtons: [SettingsTab: SettingsTabButton] = [:]
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var cancelStatus: (() -> Void)?
    private let contentHost = LayerView()
    let general = GeneralSettingsPane()
    let extensions = ExtensionsSettingsPane()
    let advanced = AdvancedSettingsPane()

    private let recorderOverlay = RecorderOverlayView()
    private var recording: Recording?
    private var cancelCountdown: (() -> Void)?
    private var cancelCountdownTick: (() -> Void)?

    /// The hotkey being recorded.
    private struct Recording {
        var title: String
        var session: HotkeyRecordingSession
        /// 0…1 while the auto-save counts down.
        var countdown: Double?
    }

    init(
        environment: SettingsWindowEnvironment,
        icons: IconProviding,
        hotkeys: HotkeyRegistering,
        keyCode: @escaping (KeySpec) -> UInt16?
    ) {
        self.environment = environment
        self.icons = icons
        self.hotkeys = hotkeys
        self.keyCode = keyCode
        settings = environment.settings()
        issues = environment.issues()
        items = environment.items()
        theme = environment.theme()

        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Soprano Cast Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        super.init(window: window)
        window.delegate = self
        window.contentView = rootView
        window.onKeyEvent = { [weak self] event in self?.handleKeyEvent(event) ?? false }

        for pane in [general, extensions, advanced] as [any SettingsPane] {
            pane.host = self
        }
        icons.onLoad = { [weak self] in self?.extensions.reloadIcons() }
        buildLayout()
        applyTheme()
        show(tab: .general)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Showing

    /// Brings the window to the front (activating Soprano Cast), on `tab` when given.
    func present(tab: SettingsTab? = nil) {
        if let tab {
            show(tab: tab)
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func show(tab: SettingsTab) {
        window?.endEditing(for: nil)
        currentTab = tab
        for (key, button) in tabButtons {
            button.isActive = key == tab
        }
        let pane = pane(for: tab)
        if pane.superview !== contentHost {
            for view in contentHost.subviews {
                view.removeFromSuperview()
            }
            pane.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                pane.topAnchor.constraint(equalTo: contentHost.topAnchor),
                pane.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            ])
        }
        pane.reload()
    }

    func windowWillClose(_ notification: Notification) {
        endRecording()
    }

    // MARK: - Changes from the app

    /// settings.json changed (this window's own edits included); redraws when the settings,
    /// their issues or the items they make (quicklinks) differ from what is showing.
    func settingsDidChange() {
        let newSettings = environment.settings()
        let newIssues = environment.issues()
        let newItems = environment.items()
        guard newSettings != settings || newIssues != issues || newItems != items else { return }
        settings = newSettings
        issues = newIssues
        items = newItems
        pane(for: currentTab).reload()
    }

    /// The launcher's item list changed (apps installed, scripts edited).
    func itemsDidChange() {
        items = environment.items()
        pane(for: currentTab).reload()
    }

    func themeDidChange() {
        theme = environment.theme()
        applyTheme()
    }

    // MARK: - SettingsHost

    @discardableResult
    func apply(_ edits: [SettingsEdit]) -> Bool {
        // Earlier edits may have landed even when a later one fails.
        defer { settingsDidChange() }
        for edit in edits {
            do {
                try environment.editSettings(edit)
            } catch let error as SettingsEditError {
                showStatus("settings.json line \(error.line): \(error.message)", isError: true)
                return false
            } catch {
                showStatus("Couldn't edit settings.json: \(error.localizedDescription)", isError: true)
                return false
            }
        }
        return true
    }

    func showStatus(_ text: String, isError: Bool) {
        cancelStatus?()
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? theme.colors.danger : theme.colors.textMuted
        statusLabel.isHidden = false
        cancelStatus = environment.schedule(Self.statusMilliseconds) { [weak self] in
            self?.statusLabel.isHidden = true
            self?.statusLabel.stringValue = ""
        }
    }

    /// The status line's text while it shows, for tests and the harness.
    var statusText: String? {
        statusLabel.isHidden || statusLabel.stringValue.isEmpty ? nil : statusLabel.stringValue
    }

    func openSettingsFile() {
        environment.openSettingsFile()
    }

    func revealSettingsFile() {
        environment.revealSettingsFile()
    }

    func chooseFolder(_ completion: @escaping @MainActor (String) -> Void) {
        environment.chooseFolder(completion)
    }

    // MARK: - Hotkey recorder

    /// Whether the recorder card is open.
    var isRecording: Bool { recording != nil }

    /// The recorder card's keycaps while it is open, for tests.
    var recorderKeys: [String]? { recording == nil ? nil : recorderOverlay.shownKeys }

    func recordHotkey(for target: HotkeyTarget, title: String) {
        window?.endEditing(for: nil)
        let current: HotkeySpec? = switch target {
        case .launcher: settings.launcher.hotkey
        case .item(let id): settings.hotkeys[id]
        }
        if recording == nil {
            hotkeys.suspend()
        }
        stopCountdown()
        recording = Recording(title: title, session: HotkeyRecordingSession(target: target, current: current))
        recorderOverlay.onCancel = { [weak self] in self?.endRecording() }
        recorderOverlay.isHidden = false
        renderRecorder()
    }

    /// Every keyDown, keyUp and flagsChanged while the window is key; the recorder takes
    /// them all while it is open.
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard recording != nil else { return false }
        if let keyEvent = KeyEventConversion.keyEvent(from: event) {
            receive(keyEvent)
        }
        return true
    }

    /// One key event for the recorder (the harness and the tests replay them here).
    func receive(_ event: KeyEvent) {
        guard var current = recording else { return }
        let target = current.session.target
        let step = current.session.handle(event) { [self] spec in owner(of: spec, except: target) }
        recording = current
        perform(step)
    }

    private func perform(_ step: HotkeyRecordingSession.Step) {
        guard let current = recording else { return }
        switch step {
        case .none:
            break
        case .redraw:
            stopCountdown()
            recording?.countdown = nil
        case .startCountdown:
            startCountdown()
        case .save(let spec, let takingFrom):
            endRecording()
            var edits: [SettingsEdit] = []
            if case .item(let other) = takingFrom {
                edits.append(.remove(["hotkeys", other.rawValue]))
            }
            edits.append(.set(spec.settingsText, Self.hotkeyPath(current.session.target)))
            apply(edits)
            return
        case .clear:
            endRecording()
            let edit: SettingsEdit? = switch current.session.target {
            // No hotkey at all: removing the key would bring back ⌘Space.
            case .launcher: settings.launcher.hotkey == nil ? nil : .set(NSNull(), ["launcher", "hotkey"])
            case .item(let id): settings.hotkeys[id] == nil ? nil : .remove(["hotkeys", id.rawValue])
            }
            if let edit {
                apply([edit])
            }
            return
        case .close:
            endRecording()
            return
        }
        renderRecorder()
    }

    private static func hotkeyPath(_ target: HotkeyTarget) -> [String] {
        switch target {
        case .launcher: ["launcher", "hotkey"]
        case .item(let id): ["hotkeys", id.rawValue]
        }
    }

    /// The target already using `spec`, comparing keys by position (the launcher's rule).
    private func owner(of spec: HotkeySpec, except target: HotkeyTarget) -> HotkeyTarget? {
        HotkeyConflicts.owner(
            of: spec,
            in: settings.hotkeyBindings,
            except: target,
            hyperIncludesShift: settings.hyperKey.includeShift,
            keyCode: keyCode
        )
    }

    private func commitRecording() {
        guard let current = recording else { return }
        let target = current.session.target
        perform(current.session.commit { [self] spec in owner(of: spec, except: target) })
    }

    private func endRecording() {
        guard recording != nil else { return }
        stopCountdown()
        recording = nil
        recorderOverlay.isHidden = true
        hotkeys.resume()
    }

    private func startCountdown() {
        stopCountdown()
        recording?.countdown = 0
        cancelCountdown = environment.schedule(HotkeyRecordingSession.countdownMilliseconds) { [weak self] in
            self?.commitRecording()
        }
        scheduleCountdownTick(elapsed: 0)
    }

    private func scheduleCountdownTick(elapsed: Int) {
        let total = HotkeyRecordingSession.countdownMilliseconds
        let tick = HotkeyRecordingSession.tickMilliseconds
        cancelCountdownTick = environment.schedule(tick) { [weak self] in
            guard let self, recording != nil else { return }
            let now = elapsed + tick
            guard now < total else { return }
            recording?.countdown = Double(now) / Double(total)
            renderRecorder()
            scheduleCountdownTick(elapsed: now)
        }
    }

    private func stopCountdown() {
        cancelCountdown?()
        cancelCountdown = nil
        cancelCountdownTick?()
        cancelCountdownTick = nil
    }

    private func renderRecorder() {
        guard let current = recording else { return }
        let keys = switch current.session.keys {
        case .spec(let spec): KeyboardLayout.keycaps(for: spec)
        case .display(let display): display
        }
        recorderOverlay.configure(
            title: current.title,
            keys: keys,
            conflict: LauncherModelBuilder.conflictText(ownerTitle: current.session.owner.map { title(of: $0) }),
            countdown: current.countdown,
            colors: theme.colors
        )
    }

    private func title(of target: HotkeyTarget) -> String {
        switch target {
        case .launcher: "Soprano Cast"
        case .item(let id): items.first { $0.id == id }?.title ?? id.rawValue
        }
    }

    // MARK: - Rendering

    /// The window's content without ordering it front (snapshot harness, tests).
    func renderImage(scale: CGFloat = 2) -> CGImage? {
        guard let window, let view = window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        extensions.prepareForRender()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.display()
        CATransaction.flush()
        guard let layer = view.layer else { return nil }
        let size = view.bounds.size
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(size.width * scale),
                  height: Int(size.height * scale),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped || view.isFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        return context.makeImage()
    }

    // MARK: - Layout

    private func pane(for tab: SettingsTab) -> any SettingsPane {
        switch tab {
        case .general: general
        case .extensions: extensions
        case .advanced: advanced
        }
    }

    private func buildLayout() {
        for view in [sidebar, contentHost, recorderOverlay] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview(view)
        }
        sidebarRule.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarRule)

        tabStack.orientation = .vertical
        tabStack.spacing = 6
        tabStack.edgeInsets = NSEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(tabStack)
        for tab in SettingsTab.allCases {
            let button = SettingsTabButton(tab: tab, theme: theme, target: self, action: #selector(tabClicked(_:)))
            tabButtons[tab] = button
            tabStack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: 34),
                button.widthAnchor.constraint(equalToConstant: Self.sidebarWidth - 20),
            ])
        }

        statusLabel.font = RetroFont.body(11)
        statusLabel.maximumNumberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(statusLabel)

        recorderOverlay.isHidden = true
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),

            sidebarRule.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarRule.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarRule.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            sidebarRule.widthAnchor.constraint(equalToConstant: Retro.hairline),

            tabStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tabStack.topAnchor.constraint(equalTo: sidebar.topAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            statusLabel.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),

            contentHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            recorderOverlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            recorderOverlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            recorderOverlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            recorderOverlay.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
    }

    private func applyTheme() {
        let colors = theme.colors
        rootView.color = colors.bgBase
        sidebar.color = colors.bgPanel
        contentHost.color = colors.bgBase
        sidebarRule.color = colors.borderStrong
        window?.backgroundColor = colors.bgBase
        for button in tabButtons.values {
            button.apply(theme: theme)
        }
        pane(for: currentTab).reload()
        renderRecorder()
    }

    @objc private func tabClicked(_ sender: SettingsTabButton) {
        show(tab: sender.tab)
    }
}

// MARK: - Window

/// Routes key events to the recorder first and handles the standard editing shortcuts
/// (Soprano Cast has no main menu to carry them).
@MainActor
final class SettingsWindow: NSWindow {
    /// Every keyDown, keyUp and flagsChanged before anything else; true when handled.
    var onKeyEvent: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if [.keyDown, .keyUp, .flagsChanged].contains(event.type), onKeyEvent?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // The recorder records ⌘W and ⌘C like any other hotkey.
        if onKeyEvent?(event) == true { return true }
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if flags == [.command], key == "w" {
            performClose(nil)
            return true
        }
        let action: Selector? = switch (flags, key) {
        case ([.command], "x"): #selector(NSText.cut(_:))
        case ([.command], "c"): #selector(NSText.copy(_:))
        case ([.command], "v"): #selector(NSText.paste(_:))
        case ([.command], "a"): #selector(NSText.selectAll(_:))
        case ([.command], "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

// MARK: - Recorder overlay

/// Dims the window and shows the launcher's recorder card in its middle; a click beside
/// the card cancels.
@MainActor
final class RecorderOverlayView: FlippedView {
    private let dim = LayerView()
    private let card = RecorderCardView()
    var onCancel: (() -> Void)?

    init() {
        super.init(frame: .zero)
        dim.translatesAutoresizingMaskIntoConstraints = true
        addSubview(dim)
        addSubview(card)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Record hotkey")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The keycaps showing.
    var shownKeys: [String] { card.shownKeys }

    func configure(title: String, keys: [String], conflict: String?, countdown: Double?, colors: ThemeColors) {
        dim.color = colors.bgBase.withAlphaComponent(0.72)
        card.configure(
            itemTitle: title,
            keys: keys,
            conflict: conflict,
            countdown: countdown,
            hint: LauncherModelBuilder.recorderHint,
            colors: colors
        )
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        dim.frame = bounds
        let size = RecorderCardView.size()
        card.frame = NSRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        card.layoutContents()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(point) {
            onCancel?()
        }
    }
}
