import AppKit
import SopranoCastCore

/// The launcher on screen: the panel (search bar, list, footer, overlays), the key monitor
/// that hands every key to the controller before a text field sees it, the HUD, and
/// offscreen rendering for the snapshot harness.
@MainActor
final class LauncherWindow: LauncherPresenting {
    /// Keeps every window off screen while still laying it out, for the snapshot harness
    /// and tests. A process whose activation policy is `.prohibited` (a plain command-line
    /// process, the test runner) is treated the same way.
    static var offscreen = false

    private(set) var isPresented = false
    var onKeyEvent: ((KeyEvent) -> Bool)?
    var onQueryChange: ((String) -> Void)?
    var onArgumentChange: ((Int, String) -> Void)?
    var onOverlayTextChange: ((String) -> Void)?
    var onRowClick: ((Int, Int) -> Void)?
    var onActionClick: ((Int) -> Void)?
    var onResignKey: (() -> Void)?

    let panel = LauncherPanel()
    let content = LauncherContentView()
    let hud = HUDWindow()
    /// The panel's AppKit frame on the display it was last presented on.
    private(set) var panelFrame = CGRect.zero

    private var model: LauncherViewModel?
    private var keyMonitor: Any?
    /// The focus and overlay last pushed to the first responder; nil forces a push.
    private var appliedFocus: LauncherFocus?
    private var appliedOverlay: String?

    init() {
        // Windows need the shared application, which a test runner has not created yet.
        _ = NSApplication.shared
        panel.contentView = content
        panel.onResignKey = { [weak self] in
            // Ordering the panel out in `dismiss` resigns key too; only a real loss counts.
            guard let self, self.isPresented else { return }
            self.onResignKey?()
        }
        content.searchBar.onQueryChange = { [weak self] text in self?.onQueryChange?(text) }
        content.searchBar.onArgumentChange = { [weak self] index, value in self?.onArgumentChange?(index, value) }
        content.actionPanel.onTextChange = { [weak self] text in self?.onOverlayTextChange?(text) }
        content.aliasEditor.onTextChange = { [weak self] text in self?.onOverlayTextChange?(text) }
        content.list.onRowClick = { [weak self] index, clickCount in self?.onRowClick?(index, clickCount) }
        content.actionPanel.onActionClick = { [weak self] index in self?.onActionClick?(index) }
        // The confirmation keys act like their keys: ↵ confirms, ⎋ cancels.
        content.confirmation.onConfirm = { [weak self] in self?.sendKey(.return, characters: "\r") }
        content.confirmation.onCancel = { [weak self] in self?.sendKey(.escape, characters: "\u{1b}") }
    }

    private var isOffscreen: Bool {
        Self.offscreen || NSApplication.shared.activationPolicy() == .prohibited
    }

    // MARK: - For tests

    /// The result row views in flat order; reused across updates.
    var rowViews: [ResultRowView] { content.list.rowViews }

    /// The argument fields' focusable controls (text fields or pop-up buttons), in order.
    var argumentControls: [NSControl] { content.searchBar.argumentBoxes.map(\.control) }

    /// The control holding keyboard focus: a text field being edited (not its field
    /// editor), the pop-up button or output text view; nil when the panel itself has it.
    var focusedView: NSView? {
        guard let responder = panel.firstResponder else { return nil }
        if let editor = responder as? NSTextView, editor.isFieldEditor, let control = editor.delegate as? NSView {
            return control
        }
        return responder as? NSView
    }

    var isHUDShowing: Bool { hud.isShowing }

    // MARK: - LauncherPresenting

    var visibleRowCount: Int {
        ResultListView.visibleRowCount(height: content.listFrame.height)
    }

    func present(_ model: LauncherViewModel, screenFrame: CGRect) {
        if !isPresented {
            appliedFocus = nil
            appliedOverlay = nil
        }
        isPresented = true
        panelFrame = Self.panelFrame(in: screenFrame)
        if panel.frame != panelFrame {
            panel.setFrame(panelFrame, display: false)
        }
        draw(model)
        guard !isOffscreen else { return }
        installKeyMonitor()
        panel.alphaValue = 1
        // A non-activating panel becomes key without activating Soprano Cast: the app
        // behind keeps its focus while typing reaches the fields.
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
    }

    func update(_ model: LauncherViewModel) {
        draw(model)
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        appliedFocus = nil
        appliedOverlay = nil
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func showHUD(_ text: String, screenFrame: CGRect) {
        hud.show(text, screenFrame: screenFrame, theme: model?.theme ?? .folioPaper, onScreen: !isOffscreen)
    }

    func renderSnapshot(screenFrame: CGRect, scale: CGFloat, backdrop: CGImage?) -> CGImage? {
        let scale = max(1, scale)
        let size = screenFrame.size
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let bounds = CGRect(origin: .zero, size: size)
        if let backdrop {
            context.draw(backdrop, in: bounds)
        } else {
            context.setFillColor((model?.theme ?? .folioPaper).colors.bgBase.cgColor)
            context.fill(bounds)
        }
        // AppKit frames → this context: same orientation, origin at the display's corner.
        if isPresented, let model {
            content.renderLayerTree(
                in: context,
                at: CGPoint(x: panelFrame.minX - screenFrame.minX, y: panelFrame.minY - screenFrame.minY),
                shadow: model.theme.colors.shadowE3
            )
        }
        hud.render(in: context, screenFrame: screenFrame)
        return context.makeImage()
    }

    /// The panel's AppKit frame: centered horizontally on `screenFrame`, its top edge a
    /// fifth of the display's height below the top, on whole points.
    static func panelFrame(in screenFrame: CGRect) -> CGRect {
        let size = LauncherPanel.size
        let top = screenFrame.maxY - screenFrame.height / 5
        return CGRect(
            x: (screenFrame.midX - size.width / 2).rounded(),
            y: (top - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Drawing and focus

    private func draw(_ model: LauncherViewModel) {
        self.model = model
        panel.appearance = model.theme.appearance.nsAppearance
        content.apply(model)
        if panel.isVisible {
            panel.invalidateShadow()
        }
        applyFocus(model)
    }

    /// Moves the first responder to the field `model.focus` names when the focus or the
    /// overlay changed, or when the focused control went away. Otherwise a field the user
    /// clicked into keeps focus, and the caret stays where it is.
    private func applyFocus(_ model: LauncherViewModel) {
        let overlay = Self.overlayKind(model.overlay)
        let target = content.responder(for: model.focus, overlay: model.overlay)
        let current = focusedView
        let currentGone = current.map { $0.window !== panel || $0.isHiddenOrHasHiddenAncestor } ?? true
        let changed = model.focus != appliedFocus || overlay != appliedOverlay
        appliedFocus = model.focus
        appliedOverlay = overlay
        guard changed || (target != nil && currentGone) else { return }
        guard let target else {
            if current != nil {
                panel.makeFirstResponder(nil)
            }
            return
        }
        guard current !== target else { return }
        panel.makeFirstResponder(target)
        if let field = target as? NSTextField {
            LauncherText.moveCaretToEnd(field, caret: model.theme.colors.caret)
        }
    }

    private static func overlayKind(_ overlay: OverlayViewModel) -> String {
        switch overlay {
        case .none: "none"
        case .actionPanel: "actionPanel"
        case .recorder: "recorder"
        case .aliasEditor: "aliasEditor"
        case .output: "output"
        case .confirmation: "confirmation"
        }
    }

    // MARK: - Keys

    /// keyDown and flagsChanged reach the controller first while the panel is key; an
    /// event it handles never reaches the text fields.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // The monitor runs on the main thread; NSEvent is not Sendable, so hand the
            // result out of the isolated block through locals.
            nonisolated(unsafe) let incoming = event
            nonisolated(unsafe) var consumed = false
            MainActor.assumeIsolated {
                consumed = self?.handle(incoming) ?? false
            }
            return consumed ? nil : incoming
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isPresented, panel.isKeyWindow, let keyEvent = KeyEventConversion.keyEvent(from: event) else {
            return false
        }
        return onKeyEvent?(keyEvent) ?? false
    }

    private func sendKey(_ key: NamedKey, characters: String) {
        let event = KeyEvent(
            kind: .keyDown,
            keyCode: key.keyCodes[0],
            modifiers: [],
            characters: characters,
            baseCharacters: characters,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        _ = onKeyEvent?(event)
    }
}
