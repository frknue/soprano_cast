import AppKit
import SopranoCastCore

/// The HUD (Folio `.hud`): a short message ("Copied", "Left Half") in a borderless panel
/// centered 1/6 up from the bottom of the display: `raised`, a `borderSubtle` hairline,
/// radius 10, the e2 shadow and SF 13 text. It fades out after 1.5 s (at once under
/// Reduce Motion); a newer message replaces it and restarts the clock.
@MainActor
final class HUDWindow {
    static let visibleDuration: TimeInterval = 1.5
    static let fadeDuration: TimeInterval = 0.2
    static let height: CGFloat = 36

    /// True from `show` until the fade-out starts.
    private(set) var isShowing = false
    private(set) var text = ""
    /// The HUD's AppKit frame.
    private(set) var frame = CGRect.zero

    private let panel: NSPanel
    private let view = HUDView()
    /// Bumped on every show so a stale timer or fade completion does nothing.
    private var generation = 0
    private var shadow = AppTheme.folioPaper.colors.shadowE2

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Above the launcher panel (`.modalPanel`), which may still be fading away.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.contentView = view
    }

    /// Shows `text` on the display whose AppKit visible frame is `screenFrame`; `onScreen`
    /// false keeps the panel laid out but never ordered in (snapshots, tests).
    func show(_ text: String, screenFrame: CGRect, theme: AppTheme, onScreen: Bool) {
        generation += 1
        let shown = generation
        self.text = text
        isShowing = true
        shadow = theme.colors.shadowE2
        panel.appearance = theme.appearance.nsAppearance
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.configure(text: text, colors: theme.colors)
        let width = view.preferredWidth
        frame = CGRect(
            x: (screenFrame.midX - width / 2).rounded(),
            y: (screenFrame.minY + screenFrame.height / 6).rounded(),
            width: width,
            height: Self.height
        )
        panel.setFrame(frame, display: false)
        view.frame = CGRect(origin: .zero, size: frame.size)
        view.layoutContents()
        CATransaction.commit()
        if onScreen {
            // A zero-length group also cancels a fade-out still running from the last message.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
            panel.orderFrontRegardless()
            panel.invalidateShadow()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.visibleDuration))
            self?.fadeOut(shown)
        }
    }

    /// Renders the HUD into a snapshot context whose bounds are `screenFrame` (bottom-left
    /// origin); nothing when it is not showing.
    func render(in context: CGContext, screenFrame: CGRect) {
        guard isShowing else { return }
        view.renderLayerTree(
            in: context,
            at: CGPoint(x: frame.minX - screenFrame.minX, y: frame.minY - screenFrame.minY),
            shadow: shadow
        )
    }

    private func fadeOut(_ shown: Int) {
        guard shown == generation, isShowing else { return }
        isShowing = false
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit runs animation completions on the main thread.
            MainActor.assumeIsolated { self?.finishFade(shown) }
        })
    }

    private func finishFade(_ shown: Int) {
        guard shown == generation else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}

/// The HUD's content: the message centered in SF 13.
final class HUDView: LauncherFlippedView {
    static let horizontalPadding: CGFloat = 16
    static let minimumWidth: CGFloat = 120

    private let label = LauncherText.label()
    private(set) var preferredWidth: CGFloat = HUDView.minimumWidth

    init() {
        super.init(frame: .zero)
        label.alignment = .center
        addSubview(label)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String, colors: ThemeColors) {
        layer?.backgroundColor = colors.raised.cgColor
        layer?.borderColor = colors.borderSubtle.cgColor
        layer?.borderWidth = Chrome.hairline
        layer?.cornerRadius = Chrome.Radius.popover
        label.attributedStringValue = LauncherText.plain(text, font: ChromeFont.row, color: colors.textPrimary, alignment: .center)
        preferredWidth = max(Self.minimumWidth, LauncherText.width(of: label.attributedStringValue) + Self.horizontalPadding * 2)
        setAccessibilityLabel(text)
    }

    func layoutContents() {
        label.frame = LauncherText.lineFrame(
            minX: Self.horizontalPadding,
            maxX: bounds.width - Self.horizontalPadding,
            centerY: bounds.height / 2,
            font: ChromeFont.row
        )
    }
}
