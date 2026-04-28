import Foundation
import UIKit

struct MarkdownSyntaxStyleApplicator {
    let baseFont: UIFont
    let resolvedTheme: ResolvedEditorTheme
    let usesLargerHeadingText: Bool
    private let visibilityPolicy: MarkdownSyntaxVisibilityPolicy

    init(
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?,
        usesLargerHeadingText: Bool = false
    ) {
        self.baseFont = baseFont
        self.resolvedTheme = resolvedTheme
        self.usesLargerHeadingText = usesLargerHeadingText
        visibilityPolicy = MarkdownSyntaxVisibilityPolicy(
            syntaxMode: syntaxMode,
            revealedRange: revealedRange
        )
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: resolvedTheme.primaryText
        ]
    }

    func applyATXHeading(
        contentRange: NSRange,
        markerRange: NSRange,
        spacerRange: NSRange,
        level: Int,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(
            [
                .font: headingFont(level: level),
                .foregroundColor: resolvedTheme.headingText
            ],
            range: contentRange
        )
        attributed.addAttribute(
            .foregroundColor,
            value: resolvedTheme.syntaxMarkerText,
            range: markerRange
        )

        applySyntaxVisibility(markerRange, rule: .followsMode, in: attributed)
        applySyntaxVisibility(spacerRange, rule: .followsMode, in: attributed)
    }

    func applySetextHeading(
        contentRange: NSRange,
        underlineRange: NSRange,
        level: Int,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(
            [
                .font: setextHeadingFont(level: level),
                .foregroundColor: resolvedTheme.headingText
            ],
            range: contentRange
        )
        attributed.addAttribute(
            .foregroundColor,
            value: resolvedTheme.syntaxMarkerText,
            range: underlineRange
        )
        attributed.addAttribute(.markdownSetextHeadingUnderline, value: true, range: underlineRange)
        applySyntaxVisibility(underlineRange, rule: .followsMode, in: attributed)
    }

    func applyBlockquote(
        lineRange: NSRange,
        leadingWhitespaceRange: NSRange,
        markerRange: NSRange,
        depth: Int,
        groupID: Int,
        text: NSString,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttribute(.markdownBlockquoteDepth, value: depth, range: lineRange)
        attributed.addAttribute(.markdownBlockquoteGroupID, value: groupID, range: lineRange)
        attributed.addAttribute(.foregroundColor, value: resolvedTheme.blockquoteText, range: lineRange)
        attributed.addAttribute(.foregroundColor, value: resolvedTheme.subtleSyntaxMarkerText, range: markerRange)

        let paragraphStyle = NSMutableParagraphStyle()
        let leadingWidth = text.substring(with: leadingWhitespaceRange).measuredMarkdownWidth(using: baseFont)
        let headIndent = leadingWidth + CGFloat(depth) * 12 + 6
        paragraphStyle.firstLineHeadIndent = headIndent
        paragraphStyle.headIndent = headIndent
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        applySyntaxVisibility(markerRange, rule: .followsMode, in: attributed)
    }

    func applyList(
        fullMatch: NSRange,
        leadingWhitespaceRange: NSRange,
        spacerRange: NSRange,
        markerRange: NSRange,
        text: NSString,
        in attributed: NSMutableAttributedString
    ) {
        let taskCheckboxRange = taskCheckboxRange(
            fullMatch: fullMatch,
            spacerRange: spacerRange,
            text: text
        )
        let markerColor = taskCheckboxRange == nil ? resolvedTheme.syntaxMarkerText : resolvedTheme.accent
        attributed.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
        if let taskCheckboxRange {
            attributed.addAttributes(
                [
                    .foregroundColor: taskCheckboxColor(in: taskCheckboxRange, text: text),
                    .markdownTaskCheckbox: true
                ],
                range: taskCheckboxRange
            )
            applyPartialTaskCheckboxColorIfNeeded(
                in: taskCheckboxRange,
                text: text,
                attributed: attributed
            )
        }

        let prefixRange = NSRange(
            location: leadingWhitespaceRange.location,
            length: NSMaxRange(spacerRange) - leadingWhitespaceRange.location
        )
        let paragraphStyle = NSMutableParagraphStyle()
        let prefixWidth = text.substring(with: prefixRange).measuredMarkdownWidth(using: baseFont)
        let leadingWidth = text.substring(with: leadingWhitespaceRange).measuredMarkdownWidth(using: baseFont)
        paragraphStyle.firstLineHeadIndent = leadingWidth
        paragraphStyle.headIndent = prefixWidth
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullMatch)
    }

    func applyIndentedCodeBlock(
        range: NSRange,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(
            [
                .font: codeBlockFont,
                .foregroundColor: resolvedTheme.codeBlockText,
                .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.block.rawValue
            ],
            range: range
        )
    }

    func applyFencedCodeBlock(
        _ match: MarkdownFencedCodeBlock,
        in attributed: NSMutableAttributedString
    ) {
        if match.contentRange.length > 0 {
            attributed.addAttributes(
                [
                    .font: codeBlockFont,
                    .foregroundColor: resolvedTheme.codeBlockText,
                    .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.block.rawValue
                ],
                range: match.contentRange
            )
        }

        applySyntaxVisibility(match.openingFenceRange, rule: .followsMode, in: attributed)

        if let closingFenceRange = match.closingFenceRange {
            applySyntaxVisibility(closingFenceRange, rule: .followsMode, in: attributed)
        }
    }

    func applyInlineCode(
        _ match: MarkdownCodeSpan,
        in attributed: NSMutableAttributedString
    ) {
        let openMarkerRange = NSRange(location: match.fullRange.location, length: match.delimiterLength)
        let closeMarkerRange = NSRange(
            location: NSMaxRange(match.fullRange) - match.delimiterLength,
            length: match.delimiterLength
        )

        attributed.addAttributes(
            [
                .font: inlineCodeFont,
                .foregroundColor: resolvedTheme.inlineCodeText,
                .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.inline.rawValue
            ],
            range: match.contentRange
        )
        applySyntaxVisibility(openMarkerRange, rule: .followsMode, in: attributed)
        applySyntaxVisibility(closeMarkerRange, rule: .followsMode, in: attributed)
    }

    func applyInlineContent(
        range: NSRange,
        in attributed: NSMutableAttributedString,
        transform: (UIFont) -> UIFont,
        additionalAttributes: [NSAttributedString.Key: Any]
    ) {
        applyFontTransform(in: attributed, range: range, transform: transform)
        for (key, value) in additionalAttributes {
            attributed.addAttribute(key, value: value, range: range)
        }
    }

    func applyDelimitedInlineSpan(
        _ span: MarkdownDelimitedInlineSpan,
        in attributed: NSMutableAttributedString
    ) {
        switch span.style {
        case .boldItalic:
            applyInlineContent(
                range: span.contentRange,
                in: attributed,
                transform: { font in
                    transformedFont(font, adding: [.traitBold, .traitItalic])
                        ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
                },
                additionalAttributes: [.foregroundColor: resolvedTheme.emphasisText]
            )
        case .bold:
            applyInlineContent(
                range: span.contentRange,
                in: attributed,
                transform: { font in
                    transformedFont(font, adding: .traitBold)
                        ?? UIFont.boldSystemFont(ofSize: font.pointSize)
                },
                additionalAttributes: [.foregroundColor: resolvedTheme.emphasisText]
            )
        case .italic:
            applyInlineContent(
                range: span.contentRange,
                in: attributed,
                transform: { font in
                    transformedFont(font, adding: .traitItalic)
                        ?? UIFont.italicSystemFont(ofSize: font.pointSize)
                },
                additionalAttributes: [.foregroundColor: resolvedTheme.emphasisText]
            )
        case .strikethrough:
            applyInlineContent(
                range: span.contentRange,
                in: attributed,
                transform: { font in font },
                additionalAttributes: [
                    .foregroundColor: resolvedTheme.strikethroughText,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
            )
        }

        applySyntaxMarkerRanges(span.markerRanges, in: attributed)
    }

    func applySyntaxMarkerRanges(
        _ ranges: [NSRange],
        color: UIColor? = nil,
        rule: MarkdownSyntaxVisibilityRule = .followsMode,
        in attributed: NSMutableAttributedString
    ) {
        for range in ranges where range.length > 0 {
            attributed.addAttribute(
                .foregroundColor,
                value: color ?? resolvedTheme.syntaxMarkerText,
                range: range
            )
            applySyntaxVisibility(range, rule: rule, in: attributed)
        }
    }

    func applyHorizontalRule(
        range: NSRange,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(
            [
                .foregroundColor: resolvedTheme.horizontalRuleText,
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
                .markdownHorizontalRule: true
            ],
            range: range
        )
        applySyntaxVisibility(range, rule: .followsMode, in: attributed)
    }

    func applyLink(
        titleRange: NSRange,
        rawDestination: String? = nil,
        destinationURL: URL?,
        hiddenRanges: [NSRange],
        in attributed: NSMutableAttributedString
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: resolvedTheme.linkText,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        if let destinationURL {
            attributes[.markdownLinkDestination] = destinationURL
        }
        if let rawDestination, rawDestination.isEmpty == false {
            attributes[.markdownLinkRawDestination] = rawDestination
        }
        attributed.addAttributes(attributes, range: titleRange)
        applySyntaxMarkerRanges(hiddenRanges, in: attributed)
    }

    func applyImage(
        altTextRange: NSRange,
        hiddenRanges: [NSRange],
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(
            [
                .font: imageAltFont,
                .foregroundColor: resolvedTheme.imageAltText
            ],
            range: altTextRange
        )
        applySyntaxMarkerRanges(
            hiddenRanges,
            color: resolvedTheme.subtleSyntaxMarkerText,
            in: attributed
        )
    }

    // Centralizing hidden syntax attributes keeps marker hiding consistent
    // between full renders and current-line visibility updates.
    func applySyntaxVisibility(
        _ range: NSRange,
        rule: MarkdownSyntaxVisibilityRule,
        in attributed: NSMutableAttributedString
    ) {
        guard range.length > 0 else {
            return
        }

        attributed.addAttribute(.markdownSyntaxToken, value: rule.rawValue, range: range)

        if visibilityPolicy.shouldHideSyntax(in: range, rule: rule) {
            applyHiddenSyntaxAttributes(range, in: attributed)
        } else {
            attributed.removeAttribute(.markdownHiddenSyntax, range: range)
        }
    }

    func applyHiddenSyntaxAttributes(
        _ range: NSRange,
        in attributed: NSMutableAttributedString
    ) {
        guard range.length > 0 else {
            return
        }

        attributed.addAttribute(.markdownHiddenSyntax, value: true, range: range)
        attributed.removeAttribute(.kern, range: range)
    }

    func transformedFont(
        _ font: UIFont,
        adding traits: UIFontDescriptor.SymbolicTraits,
        size: CGFloat? = nil
    ) -> UIFont? {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
        guard let descriptor else {
            return nil
        }

        return UIFont(descriptor: descriptor, size: size ?? font.pointSize)
    }

    private var inlineCodeFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
    }

    private var codeBlockFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
    }

    private var imageAltFont: UIFont {
        transformedFont(baseFont, adding: .traitItalic)
            ?? UIFont.italicSystemFont(ofSize: baseFont.pointSize)
    }

    private func headingFont(level: Int) -> UIFont {
        let scale = usesLargerHeadingText ? max(1.0, 1.5 - CGFloat(level - 1) * 0.08) : 1.0
        return transformedFont(baseFont, adding: .traitBold, size: baseFont.pointSize * scale)
            ?? UIFont.boldSystemFont(ofSize: baseFont.pointSize * scale)
    }

    private func setextHeadingFont(level: Int) -> UIFont {
        let scale: CGFloat
        if usesLargerHeadingText {
            scale = level == 1 ? 1.5 : 1.42
        } else {
            scale = 1.0
        }
        return transformedFont(baseFont, adding: .traitBold, size: baseFont.pointSize * scale)
            ?? UIFont.boldSystemFont(ofSize: baseFont.pointSize * scale)
    }

    private func applyFontTransform(
        in attributed: NSMutableAttributedString,
        range: NSRange,
        transform: (UIFont) -> UIFont
    ) {
        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let currentFont = (value as? UIFont) ?? baseFont
            attributed.addAttribute(.font, value: transform(currentFont), range: subrange)
        }
    }

    private func taskCheckboxRange(
        fullMatch: NSRange,
        spacerRange: NSRange,
        text: NSString
    ) -> NSRange? {
        let contentStart = NSMaxRange(spacerRange)
        let fullEnd = NSMaxRange(fullMatch)
        guard fullEnd - contentStart >= 3 else {
            return nil
        }

        let openBracket = text.character(at: contentStart)
        let checkboxState = text.character(at: contentStart + 1)
        let closeBracket = text.character(at: contentStart + 2)
        guard openBracket == 0x5B, closeBracket == 0x5D else {
            return nil
        }

        guard checkboxState == 0x20 || checkboxState == 0x78 || checkboxState == 0x58 || checkboxState == 0x2F else {
            return nil
        }

        return NSRange(location: contentStart, length: 3)
    }

    private func taskCheckboxColor(in checkboxRange: NSRange, text: NSString) -> UIColor {
        let state = text.character(at: checkboxRange.location + 1)
        return state == 0x78 || state == 0x58
            ? resolvedTheme.checkboxChecked
            : resolvedTheme.checkboxUnchecked
    }

    private func applyPartialTaskCheckboxColorIfNeeded(
        in checkboxRange: NSRange,
        text: NSString,
        attributed: NSMutableAttributedString
    ) {
        guard text.character(at: checkboxRange.location + 1) == 0x2F else {
            return
        }

        attributed.addAttribute(
            .foregroundColor,
            value: resolvedTheme.checkboxChecked,
            range: checkboxRange
        )
        attributed.addAttribute(
            .foregroundColor,
            value: resolvedTheme.checkboxUnchecked,
            range: NSRange(location: checkboxRange.location + 1, length: 1)
        )
    }
}

private extension String {
    func measuredMarkdownWidth(using font: UIFont) -> CGFloat {
        (self as NSString).size(withAttributes: [.font: font]).width
    }
}
