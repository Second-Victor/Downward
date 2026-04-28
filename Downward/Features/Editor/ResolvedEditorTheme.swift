import SwiftUI
import UIKit

/// Resolved runtime theme roles for the shipping editor stack.
/// Future custom themes and JSON import/export should map into this type so the renderer,
/// TextKit drawing, editor surface, and keyboard accessory all consume the same palette.
struct ResolvedEditorTheme: Equatable {
    private static let chromeLuminanceThreshold = 0.5

    let editorBackground: UIColor
    /// Reserved theme color for keyboard-adjacent surfaces. The shipping accessory host stays
    /// clear/non-opaque so UIKit's own keyboard material shows through without repainting
    /// private keyboard wrapper views.
    let keyboardAccessoryUnderlayBackground: UIColor
    let accent: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let tertiaryText: UIColor
    let headingText: UIColor
    let emphasisText: UIColor
    let strikethroughText: UIColor
    let syntaxMarkerText: UIColor
    let subtleSyntaxMarkerText: UIColor
    let linkText: UIColor
    let imageAltText: UIColor
    let inlineCodeText: UIColor
    let inlineCodeBackground: UIColor
    let codeBlockText: UIColor
    let codeBlockBackground: UIColor
    let blockquoteText: UIColor
    let blockquoteBackground: UIColor
    let blockquoteBar: UIColor
    let horizontalRuleText: UIColor
    let checkboxUnchecked: UIColor
    let checkboxChecked: UIColor

    nonisolated static let `default` = ResolvedEditorTheme(
        editorBackground: .systemBackground,
        keyboardAccessoryUnderlayBackground: .systemBackground,
        accent: .systemBlue,
        primaryText: .label,
        secondaryText: .secondaryLabel,
        tertiaryText: .tertiaryLabel,
        headingText: .label,
        emphasisText: .label,
        strikethroughText: .label,
        syntaxMarkerText: .secondaryLabel,
        subtleSyntaxMarkerText: .tertiaryLabel,
        linkText: .link,
        imageAltText: .secondaryLabel,
        inlineCodeText: .label,
        inlineCodeBackground: .secondarySystemFill,
        codeBlockText: .label,
        codeBlockBackground: .secondarySystemFill,
        blockquoteText: .label,
        blockquoteBackground: .secondarySystemFill,
        blockquoteBar: .tertiaryLabel,
        horizontalRuleText: .tertiaryLabel,
        checkboxUnchecked: .systemRed,
        checkboxChecked: .systemGreen
    )

    static func == (lhs: ResolvedEditorTheme, rhs: ResolvedEditorTheme) -> Bool {
        lhs.editorBackground.isEqual(rhs.editorBackground)
            && lhs.keyboardAccessoryUnderlayBackground.isEqual(rhs.keyboardAccessoryUnderlayBackground)
            && lhs.accent.isEqual(rhs.accent)
            && lhs.primaryText.isEqual(rhs.primaryText)
            && lhs.secondaryText.isEqual(rhs.secondaryText)
            && lhs.tertiaryText.isEqual(rhs.tertiaryText)
            && lhs.headingText.isEqual(rhs.headingText)
            && lhs.emphasisText.isEqual(rhs.emphasisText)
            && lhs.strikethroughText.isEqual(rhs.strikethroughText)
            && lhs.syntaxMarkerText.isEqual(rhs.syntaxMarkerText)
            && lhs.subtleSyntaxMarkerText.isEqual(rhs.subtleSyntaxMarkerText)
            && lhs.linkText.isEqual(rhs.linkText)
            && lhs.imageAltText.isEqual(rhs.imageAltText)
            && lhs.inlineCodeText.isEqual(rhs.inlineCodeText)
            && lhs.inlineCodeBackground.isEqual(rhs.inlineCodeBackground)
            && lhs.codeBlockText.isEqual(rhs.codeBlockText)
            && lhs.codeBlockBackground.isEqual(rhs.codeBlockBackground)
            && lhs.blockquoteText.isEqual(rhs.blockquoteText)
            && lhs.blockquoteBackground.isEqual(rhs.blockquoteBackground)
            && lhs.blockquoteBar.isEqual(rhs.blockquoteBar)
            && lhs.horizontalRuleText.isEqual(rhs.horizontalRuleText)
            && lhs.checkboxUnchecked.isEqual(rhs.checkboxUnchecked)
            && lhs.checkboxChecked.isEqual(rhs.checkboxChecked)
    }

    func applyingColorFormattedText(_ isEnabled: Bool) -> ResolvedEditorTheme {
        guard isEnabled else {
            return self
        }

        return ResolvedEditorTheme(
            editorBackground: editorBackground,
            keyboardAccessoryUnderlayBackground: keyboardAccessoryUnderlayBackground,
            accent: accent,
            primaryText: primaryText,
            secondaryText: secondaryText,
            tertiaryText: tertiaryText,
            headingText: accent,
            emphasisText: syntaxMarkerText,
            strikethroughText: strikethroughText,
            syntaxMarkerText: syntaxMarkerText,
            subtleSyntaxMarkerText: subtleSyntaxMarkerText,
            linkText: linkText,
            imageAltText: imageAltText,
            inlineCodeText: inlineCodeText,
            inlineCodeBackground: inlineCodeBackground,
            codeBlockText: codeBlockText,
            codeBlockBackground: codeBlockBackground,
            blockquoteText: blockquoteText,
            blockquoteBackground: blockquoteBackground,
            blockquoteBar: blockquoteBar,
            horizontalRuleText: horizontalRuleText,
            checkboxUnchecked: checkboxUnchecked,
            checkboxChecked: checkboxChecked
        )
    }

    /// SwiftUI uses `.dark` color scheme to request light status-bar/navigation foregrounds.
    /// Resolve adaptive colors against the current app scheme before measuring luminance so
    /// system themes keep following the phone/app appearance naturally.
    func preferredChromeColorScheme(resolvingAgainst colorScheme: ColorScheme) -> ColorScheme {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme.userInterfaceStyle)
        let resolvedBackground = editorBackground.resolvedColor(with: traits)

        return resolvedBackground.wcagRelativeLuminance < Self.chromeLuminanceThreshold ? .dark : .light
    }
}

private extension ColorScheme {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark:
            .dark
        case .light:
            .light
        @unknown default:
            .unspecified
        }
    }
}
