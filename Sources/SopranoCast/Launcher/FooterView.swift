import AppKit
import SopranoCastCore

/// The 40 pt footer on the panel's surface with a `borderSubtle` hairline on top. Left:
/// the Cast glyph and "Soprano Cast" (SF 12 muted), or a toast (`danger` for an error) in
/// their place. Right: the primary action's title (ink) with its ↵ cap, a separator, and
/// "Actions" with one ⌘K cap.
final class FooterView: LauncherFlippedView {
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 12
    static let glyphSide: CGFloat = 14
    static let keycapHeight: CGFloat = Chrome.keycapHeight
    static let brand = "Soprano Cast"

    private let rule = LauncherFlippedView()
    private let glyphLayer = CALayer()
    private let brandLabel = LauncherText.label()
    private let toastLabel = LauncherText.label()
    private let primaryLabel = LauncherText.label()
    private let primaryKeys = KeycapRowView()
    private let separator = LauncherFlippedView()
    private let actionsLabel = LauncherText.label()
    private let actionsKeys = KeycapRowView()
    private var glyphColor: NSColor?

    /// The toast showing, nil when the brand shows.
    private(set) var toastText: String?

    init() {
        super.init(frame: .zero)
        glyphLayer.contentsGravity = .resizeAspect
        glyphLayer.contentsScale = 2
        layer?.addSublayer(glyphLayer)
        for view: NSView in [rule, brandLabel, toastLabel, primaryLabel, primaryKeys, separator, actionsLabel, actionsKeys] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ footer: FooterViewModel, theme: AppTheme) {
        let colors = theme.colors
        rule.layer?.backgroundColor = colors.borderSubtle.cgColor
        separator.layer?.backgroundColor = colors.borderSubtle.cgColor
        if glyphColor != colors.textMuted {
            glyphColor = colors.textMuted
            let glyph = CastGlyph.image(side: Self.glyphSide, lineWidth: 1.4, color: colors.textMuted)
            glyphLayer.contents = LauncherText.cgImage(glyph, side: Self.glyphSide, scale: glyphLayer.contentsScale)
        }
        toastText = footer.toast
        brandLabel.attributedStringValue = LauncherText.plain(Self.brand, font: ChromeFont.label, color: colors.textMuted)
        toastLabel.attributedStringValue = LauncherText.plain(
            footer.toast ?? "", font: ChromeFont.label, color: footer.toastIsError ? colors.danger : colors.textPrimary
        )
        primaryLabel.attributedStringValue = LauncherText.plain(
            footer.primaryTitle ?? "", font: ChromeFont.label, color: colors.textPrimary, alignment: .right
        )
        primaryKeys.configure(keys: ["↵"], colors: colors)
        actionsLabel.attributedStringValue = LauncherText.plain("Actions", font: ChromeFont.label, color: colors.textMuted, alignment: .right)
        actionsKeys.configure(keys: ["⌘K"], colors: colors)
        layoutContents(showsPrimary: footer.primaryTitle != nil, showsActions: footer.showsActions)
    }

    private func layoutContents(showsPrimary: Bool, showsActions: Bool) {
        let centerY = ((Chrome.hairline + bounds.height) / 2).rounded()
        rule.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Chrome.hairline)

        // Right side, laid out from the trailing edge.
        var trailing = bounds.width - Self.trailingInset
        actionsKeys.isHidden = !showsActions
        actionsLabel.isHidden = !showsActions
        if showsActions {
            trailing = placeKeys(actionsKeys, trailing: trailing, centerY: centerY) - 8
            let width = LauncherText.width(of: actionsLabel.attributedStringValue)
            actionsLabel.frame = LauncherText.lineFrame(minX: trailing - width, maxX: trailing, centerY: centerY, font: ChromeFont.label)
            trailing -= width
        }
        let separated = showsPrimary && showsActions
        separator.isHidden = !separated
        if separated {
            trailing -= 14
            separator.frame = CGRect(x: trailing - Chrome.hairline, y: centerY - 8, width: Chrome.hairline, height: 16)
            trailing -= Chrome.hairline + 14
        }
        primaryKeys.isHidden = !showsPrimary
        primaryLabel.isHidden = !showsPrimary
        let leftLimit = bounds.width / 2
        if showsPrimary {
            trailing = placeKeys(primaryKeys, trailing: trailing, centerY: centerY) - 8
            let width = min(LauncherText.width(of: primaryLabel.attributedStringValue), max(0, trailing - leftLimit))
            primaryLabel.frame = LauncherText.lineFrame(minX: trailing - width, maxX: trailing, centerY: centerY, font: ChromeFont.label)
            trailing -= width
        }

        // Left side: the toast replaces the glyph and the brand.
        let leftMax = max(Self.leadingInset, trailing - 16)
        let showsToast = toastText != nil
        toastLabel.isHidden = !showsToast
        glyphLayer.isHidden = showsToast
        brandLabel.isHidden = showsToast
        if showsToast {
            toastLabel.frame = LauncherText.lineFrame(
                minX: Self.leadingInset, maxX: leftMax, centerY: centerY, font: ChromeFont.label
            )
        } else {
            glyphLayer.frame = CGRect(
                x: Self.leadingInset,
                y: centerY - Self.glyphSide / 2,
                width: Self.glyphSide,
                height: Self.glyphSide
            )
            let brandX = glyphLayer.frame.maxX + 8
            let width = min(LauncherText.width(of: brandLabel.attributedStringValue), max(0, leftMax - brandX))
            brandLabel.frame = LauncherText.lineFrame(minX: brandX, maxX: brandX + width, centerY: centerY, font: ChromeFont.label)
        }
    }

    /// Places `keys` ending at `trailing`; returns their leading edge.
    private func placeKeys(_ keys: KeycapRowView, trailing: CGFloat, centerY: CGFloat) -> CGFloat {
        keys.frame = CGRect(
            x: trailing - keys.preferredWidth,
            y: (centerY - Self.keycapHeight / 2).rounded(),
            width: keys.preferredWidth,
            height: Self.keycapHeight
        )
        keys.layoutCaps()
        return keys.frame.minX
    }
}
