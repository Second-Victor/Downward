import UIKit

/// Resolved runtime theme roles for the shipping editor stack.
/// Future custom themes and JSON import/export should map into this type so the renderer,
/// TextKit drawing, editor surface, and keyboard accessory all consume the same palette.
struct ResolvedEditorTheme: Equatable {
    let editorBackground: UIColor
    /// The accessory host is painted with the editor surface color so UIKit's private keyboard
    /// wrappers cannot expose their default light background during presentation or dismissal.
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
        horizontalRuleText: .tertiaryLabel
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
            headingText: syntaxMarkerText,
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
            horizontalRuleText: horizontalRuleText
        )
    }
}
