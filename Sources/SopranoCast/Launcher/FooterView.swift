import AppKit
import SopranoCastCore

/// The 40 pt footer on `bgPanel` with a hairline on top. Left: a small stripe and
/// "soprano cast", or a toast (body 12; `danger` for an error) in their place. Right: the
/// primary action's title with its ↵ keycap, a separator, and "actions" with ⌘ K.
final class FooterView: LauncherFlippedView {
    static let horizontalInset: CGFloat = 16
    static let stripeSize = CGSize(width: 26, height: 10)
    static let keycapHeight: CGFloat = 20
    static let brand = "soprano cast"

    private let rule = RetroRuleView(axis: .horizontal, style: .single)
    private let stripe = RetroStripeView(layout: .slanted)
    private let brandLabel = LauncherText.label()
    private let toastLabel = LauncherText.label()
    private let primaryLabel = LauncherText.label()
    private let primaryKeys = KeycapRowView()
    private let separator = RetroRuleView(axis: .vertical, style: .single)
    private let actionsLabel = LauncherText.label()
    private let actionsKeys = KeycapRowView()

    /// The toast showing, nil when the brand shows.
    private(set) var toastText: String?

    init() {
        super.init(frame: .zero)
        for view: NSView in [rule, stripe, separator] {
            view.translatesAutoresizingMaskIntoConstraints = true
        }
        for view: NSView in [rule, stripe, brandLabel, toastLabel, primaryLabel, primaryKeys, separator, actionsLabel, actionsKeys] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ footer: FooterViewModel, colors: ThemeColors) {
        layer?.backgroundColor = colors.bgPanel.cgColor
        rule.color = colors.borderSubtle
        separator.color = colors.borderSubtle
        stripe.colors = colors.stripe
        toastText = footer.toast
        brandLabel.attributedStringValue = RetroText.display(Self.brand, color: colors.textMuted)
        toastLabel.attributedStringValue = LauncherText.plain(
            footer.toast ?? "", font: RetroFont.body(12), color: footer.toastIsError ? colors.danger : colors.textPrimary
        )
        primaryLabel.attributedStringValue = LauncherText.plain(
            footer.primaryTitle ?? "", font: RetroFont.body(12), color: colors.textPrimary, alignment: .right
        )
        primaryKeys.configure(keys: ["↵"], fontSize: RetroFont.grid, height: Self.keycapHeight, colors: colors)
        actionsLabel.attributedStringValue = RetroText.display("actions", color: colors.textMuted, alignment: .right)
        actionsKeys.configure(keys: ["⌘", "K"], fontSize: RetroFont.grid, height: Self.keycapHeight, colors: colors)
        layoutContents(showsPrimary: footer.primaryTitle != nil, showsActions: footer.showsActions)
    }

    private func layoutContents(showsPrimary: Bool, showsActions: Bool) {
        let centerY = (Retro.hairline + bounds.height) / 2
        rule.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Retro.hairline)

        // Right side, laid out from the trailing edge.
        var trailing = bounds.width - Self.horizontalInset
        actionsKeys.isHidden = !showsActions
        actionsLabel.isHidden = !showsActions
        if showsActions {
            trailing = placeKeys(actionsKeys, trailing: trailing, centerY: centerY) - 6
            let width = LauncherText.width(of: actionsLabel.attributedStringValue)
            actionsLabel.frame = LauncherText.lineFrame(minX: trailing - width, maxX: trailing, centerY: centerY, font: RetroFont.display(11))
            trailing -= width
        }
        let separated = showsPrimary && showsActions
        separator.isHidden = !separated
        if separated {
            trailing -= 12
            separator.frame = CGRect(x: trailing - Retro.hairline, y: (centerY - 8).rounded(), width: Retro.hairline, height: 16)
            trailing -= Retro.hairline + 12
        }
        primaryKeys.isHidden = !showsPrimary
        primaryLabel.isHidden = !showsPrimary
        let leftLimit = bounds.width / 2
        if showsPrimary {
            trailing = placeKeys(primaryKeys, trailing: trailing, centerY: centerY) - 6
            let width = min(LauncherText.width(of: primaryLabel.attributedStringValue), max(0, trailing - leftLimit))
            primaryLabel.frame = LauncherText.lineFrame(minX: trailing - width, maxX: trailing, centerY: centerY, font: RetroFont.body(12))
            trailing -= width
        }

        // Left side: the toast replaces the stripe and the brand.
        let leftMax = max(Self.horizontalInset, trailing - 16)
        let showsToast = toastText != nil
        toastLabel.isHidden = !showsToast
        stripe.isHidden = showsToast
        brandLabel.isHidden = showsToast
        if showsToast {
            toastLabel.frame = LauncherText.lineFrame(
                minX: Self.horizontalInset, maxX: leftMax, centerY: centerY, font: RetroFont.body(12)
            )
        } else {
            stripe.frame = CGRect(
                x: Self.horizontalInset,
                y: (centerY - Self.stripeSize.height / 2).rounded(),
                width: Self.stripeSize.width,
                height: Self.stripeSize.height
            )
            let brandX = stripe.frame.maxX + 8
            let width = min(LauncherText.width(of: brandLabel.attributedStringValue), max(0, leftMax - brandX))
            brandLabel.frame = LauncherText.lineFrame(minX: brandX, maxX: brandX + width, centerY: centerY, font: RetroFont.display(11))
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
