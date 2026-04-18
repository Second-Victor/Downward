import Foundation
import UIKit

struct MarkdownStyledTextRenderer {
    struct Configuration: Equatable {
        let text: String
        let baseFont: UIFont
        let syntaxMode: MarkdownSyntaxMode
        let revealedRange: NSRange?
    }

    private struct SetextHeadingMatch {
        let contentRange: NSRange
        let underlineRange: NSRange
        let level: Int
    }

    private struct CodeSpanMatch {
        let fullRange: NSRange
        let contentRange: NSRange
        let delimiterLength: Int
    }

    private struct FencedCodeBlockMatch {
        let fullRange: NSRange
        let contentRange: NSRange
        let openingFenceRange: NSRange
        let closingFenceRange: NSRange?
    }

    func render(configuration: Configuration) -> NSAttributedString {
        let text = configuration.text
        let nsText = text as NSString
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes(font: configuration.baseFont)
        )

        let lineRanges = lineRanges(in: nsText)
        let indentedCodeBlockRanges = indentedCodeBlockRanges(in: nsText, lineRanges: lineRanges)
        let fencedCodeBlockMatches = fencedCodeBlockMatches(in: nsText, lineRanges: lineRanges)
        let fencedCodeBlockRanges = fencedCodeBlockMatches.map(\.fullRange)
        let codeBlockRanges = mergedRanges(indentedCodeBlockRanges + fencedCodeBlockRanges)
        let setextMatches = setextHeadingMatches(
            in: nsText,
            lineRanges: lineRanges,
            protectedRanges: codeBlockRanges
        )
        let setextUnderlineRanges = setextMatches.map(\.underlineRange)
        let codeSpanMatches = inlineCodeMatches(in: text, protectedRanges: codeBlockRanges)
        let codeSpanRanges = codeSpanMatches.map(\.fullRange)
        let imageRanges = imageRanges(
            in: text,
            protectedRanges: codeBlockRanges + codeSpanRanges
        )
        let emphasisProtectedRanges = codeBlockRanges + codeSpanRanges + imageRanges
        let boldItalicRanges = inlineRanges(
            matching: [
                #"(?<!\*)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*(?!\*)"#,
                #"(?<!_)___(?=\S)(.+?)(?<=\S)___(?!_)"#
            ],
            in: text,
            protectedRanges: emphasisProtectedRanges
        )
        let nestedBoldItalicRanges = inlineRanges(
            matching: [
                #"(?<!_)__(\*)(?=\S)(.+?)(?<=\S)\1__(?!_)"#,
                #"(?<!\*)\*\*(_)(?=\S)(.+?)(?<=\S)\1\*\*(?!\*)"#,
                #"(?<!_)\_(\*\*)(?=\S)(.+?)(?<=\S)\1_(?!_)"#,
                #"(?<!\*)\*(__)(?=\S)(.+?)(?<=\S)\1\*(?!\*)"#
            ],
            in: text,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges
        )
        let boldRanges = inlineRanges(
            matching: [
                #"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#,
                #"(?<!_)__(?=\S)(.+?)(?<=\S)__(?!_)"#
            ],
            in: text,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges
        )

        styleIndentedCodeBlocks(
            in: attributed,
            text: nsText,
            ranges: indentedCodeBlockRanges,
            baseFont: configuration.baseFont
        )
        styleFencedCodeBlocks(
            matches: fencedCodeBlockMatches,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont
        )
        styleSetextHeadings(
            matches: setextMatches,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleHeadings(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            protectedRanges: codeBlockRanges
        )
        styleHorizontalRules(
            in: attributed,
            text: nsText,
            lineRanges: lineRanges,
            protectedRanges: codeBlockRanges + setextUnderlineRanges,
            baseFont: configuration.baseFont
        )
        styleBlockquotes(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            protectedRanges: codeBlockRanges
        )
        styleLists(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: codeBlockRanges
        )
        styleInlineCode(
            matches: codeSpanMatches,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!\*)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!_)___(?=\S)(.+?)(?<=\S)___(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!_)__(\*)(?=\S)(.+?)(?<=\S)\1__(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!\*)\*\*(_)(?=\S)(.+?)(?<=\S)\1\*\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!_)\_(\*\*)(?=\S)(.+?)(?<=\S)\1_(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!\*)\*(__)(?=\S)(.+?)(?<=\S)\1\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitBold) ?? UIFont.boldSystemFont(ofSize: font.pointSize)
            }
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!_)__(?=\S)(.+?)(?<=\S)__(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitBold) ?? UIFont.boldSystemFont(ofSize: font.pointSize)
            }
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!\*)\*(?=\S)(.+?)(?<=\S)\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges + boldRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: font.pointSize)
            }
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!_)_(?=\S)(.+?)(?<=\S)_(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges + boldRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: font.pointSize)
            }
        )
        styleDelimitedInlinePattern(
            pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in font },
            additionalContentAttributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        styleImages(
            in: attributed,
            text: nsText,
            protectedRanges: codeBlockRanges + codeSpanRanges,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleLinks(
            in: attributed,
            text: nsText,
            protectedRanges: codeBlockRanges + codeSpanRanges + imageRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )

        return attributed
    }

    func revealedLineRange(
        for selectionRange: NSRange,
        in text: String
    ) -> NSRange? {
        guard text.isEmpty == false else {
            return nil
        }

        let nsText = text as NSString
        let safeLocation = min(selectionRange.location, nsText.length)
        let safeLength = min(selectionRange.length, nsText.length - safeLocation)
        let safeSelection = NSRange(location: safeLocation, length: safeLength)

        if safeSelection.length > 0 {
            let startLine = nsText.lineRange(for: NSRange(location: safeSelection.location, length: 0))
            let endLocation = max(safeSelection.location, NSMaxRange(safeSelection) - 1)
            let endLine = nsText.lineRange(for: NSRange(location: endLocation, length: 0))
            return NSUnionRange(startLine, endLine)
        }

        return nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
    }

    private func styleHeadings(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?,
        protectedRanges: [NSRange]
    ) {
        let regex = regex(for: #"^(#{1,6})([ \t]+)(.+)$"#, options: [.anchorsMatchLines])
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 4
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard
                protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false,
                isEscaped(location: fullMatch.location, in: text as String) == false
            else {
                return
            }

            let markerRange = match.range(at: 1)
            let spacerRange = match.range(at: 2)
            let contentRange = match.range(at: 3)
            let level = markerRange.length
            let scale = max(1.0, 1.5 - CGFloat(level - 1) * 0.08)
            let headingFont = transformedFont(baseFont, adding: .traitBold, size: baseFont.pointSize * scale)
                ?? UIFont.boldSystemFont(ofSize: baseFont.pointSize * scale)

            attributed.addAttributes(
                [
                    .font: headingFont,
                    .foregroundColor: UIColor.label
                ],
                range: contentRange
            )
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor.secondaryLabel,
                range: markerRange
            )

            hideSyntaxIfNeeded(
                markerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
            hideSyntaxIfNeeded(
                spacerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleSetextHeadings(
        matches: [SetextHeadingMatch],
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        for match in matches {
            let scale: CGFloat = match.level == 1 ? 1.5 : 1.42
            let headingFont = transformedFont(baseFont, adding: .traitBold, size: baseFont.pointSize * scale)
                ?? UIFont.boldSystemFont(ofSize: baseFont.pointSize * scale)

            attributed.addAttributes(
                [
                    .font: headingFont,
                    .foregroundColor: UIColor.label
                ],
                range: match.contentRange
            )
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor.secondaryLabel,
                range: match.underlineRange
            )
            hideSyntaxIfNeeded(
                match.underlineRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleBlockquotes(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?,
        protectedRanges: [NSRange]
    ) {
        let regex = regex(for: #"^(>[ \t]?)(.+)$"#, options: [.anchorsMatchLines])
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 3
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false else {
                return
            }

            let markerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            attributed.addAttributes(
                [
                    .font: transformedFont(baseFont, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: baseFont.pointSize),
                    .foregroundColor: UIColor.secondaryLabel
                ],
                range: contentRange
            )
            attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: markerRange)

            let paragraphStyle = NSMutableParagraphStyle()
            let markerWidth = text.substring(with: markerRange).measuredWidth(using: baseFont)
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = markerWidth + 6
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullMatch)

            hideSyntaxIfNeeded(
                markerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleLists(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        protectedRanges: [NSRange]
    ) {
        let patterns = [
            #"^([ \t]*)([*+-])([ \t]+)(.+)$"#,
            #"^([ \t]*)(\d+\.)([ \t]+)(.+)$"#
        ]
        let fullRange = NSRange(location: 0, length: text.length)

        for pattern in patterns {
            let regex = regex(for: pattern, options: [.anchorsMatchLines])
            regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
                guard
                    let match,
                    match.numberOfRanges == 5
                else {
                    return
                }

                let fullMatch = match.range(at: 0)
                guard protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false else {
                    return
                }

                let leadingWhitespaceRange = match.range(at: 1)
                let markerRange = match.range(at: 2)
                let spacerRange = match.range(at: 3)
                attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: markerRange)

                let prefixRange = NSRange(
                    location: leadingWhitespaceRange.location,
                    length: NSMaxRange(spacerRange) - leadingWhitespaceRange.location
                )
                let paragraphStyle = NSMutableParagraphStyle()
                let prefixWidth = text.substring(with: prefixRange).measuredWidth(using: baseFont)
                let leadingWidth = text.substring(with: leadingWhitespaceRange).measuredWidth(using: baseFont)
                paragraphStyle.firstLineHeadIndent = leadingWidth
                paragraphStyle.headIndent = prefixWidth
                attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullMatch)
            }
        }
    }

    private func styleIndentedCodeBlocks(
        in attributed: NSMutableAttributedString,
        text: NSString,
        ranges: [NSRange],
        baseFont: UIFont
    ) {
        guard ranges.isEmpty == false else {
            return
        }

        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
        for range in ranges {
            attributed.addAttributes(
                [
                    .font: codeFont,
                    .foregroundColor: UIColor.label,
                    .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.block.rawValue
                ],
                range: range
            )
        }
    }

    private func styleFencedCodeBlocks(
        matches: [FencedCodeBlockMatch],
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont
    ) {
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
        for match in matches {
            if match.contentRange.length > 0 {
                attributed.addAttributes(
                    [
                        .font: codeFont,
                        .foregroundColor: UIColor.label,
                        .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.block.rawValue
                    ],
                    range: match.contentRange
                )
            }

            hideRange(
                match.openingFenceRange,
                in: attributed,
                text: text,
                baseFont: baseFont
            )

            if let closingFenceRange = match.closingFenceRange {
                hideRange(
                    closingFenceRange,
                    in: attributed,
                    text: text,
                    baseFont: baseFont
                )
            }
        }
    }

    private func styleInlineCode(
        matches: [CodeSpanMatch],
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)

        for match in matches {
            let openMarkerRange = NSRange(location: match.fullRange.location, length: match.delimiterLength)
            let closeMarkerRange = NSRange(
                location: NSMaxRange(match.fullRange) - match.delimiterLength,
                length: match.delimiterLength
            )

            attributed.addAttributes(
                [
                    .font: codeFont,
                    .foregroundColor: UIColor.label,
                    .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.inline.rawValue
                ],
                range: match.contentRange
            )
            hideRange(openMarkerRange, in: attributed, text: text, baseFont: baseFont)
            hideRange(closeMarkerRange, in: attributed, text: text, baseFont: baseFont)
        }
    }

    private func styleDelimitedInlinePattern(
        pattern: String,
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        protectedRanges: [NSRange],
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?,
        contentTransform: (UIFont) -> UIFont,
        additionalContentAttributes: [NSAttributedString.Key: Any] = [:]
    ) {
        let regex = regex(for: pattern)
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 2
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard
                protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false,
                isEscaped(location: fullMatch.location, in: text as String) == false
            else {
                return
            }

            let contentRange = match.range(at: 1)
            let leadingMarkerLength = contentRange.location - fullMatch.location
            let trailingMarkerLength = NSMaxRange(fullMatch) - NSMaxRange(contentRange)
            let leadingMarkerRange = NSRange(location: fullMatch.location, length: leadingMarkerLength)
            let trailingMarkerRange = NSRange(
                location: NSMaxRange(contentRange),
                length: trailingMarkerLength
            )

            applyFontTransform(in: attributed, range: contentRange, transform: contentTransform, baseFont: baseFont)
            for (key, value) in additionalContentAttributes {
                attributed.addAttribute(key, value: value, range: contentRange)
            }

            attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: leadingMarkerRange)
            attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: trailingMarkerRange)
            hideSyntaxIfNeeded(
                leadingMarkerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
            hideSyntaxIfNeeded(
                trailingMarkerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleNestedDelimitedInlinePattern(
        pattern: String,
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        protectedRanges: [NSRange],
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?,
        contentTransform: (UIFont) -> UIFont
    ) {
        let regex = regex(for: pattern)
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 3
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard
                protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false,
                isEscaped(location: fullMatch.location, in: text as String) == false
            else {
                return
            }

            let innerMarkerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let innerMarkerLength = innerMarkerRange.length
            let leadingOuterLength = innerMarkerRange.location - fullMatch.location
            let trailingOuterLength = NSMaxRange(fullMatch) - NSMaxRange(contentRange) - innerMarkerLength

            let leadingOuterRange = NSRange(location: fullMatch.location, length: leadingOuterLength)
            let leadingInnerRange = NSRange(location: innerMarkerRange.location, length: innerMarkerLength)
            let trailingInnerRange = NSRange(location: NSMaxRange(contentRange), length: innerMarkerLength)
            let trailingOuterRange = NSRange(
                location: NSMaxRange(trailingInnerRange),
                length: trailingOuterLength
            )

            applyFontTransform(in: attributed, range: contentRange, transform: contentTransform, baseFont: baseFont)

            let markerRanges = [leadingOuterRange, leadingInnerRange, trailingInnerRange, trailingOuterRange]
            for markerRange in markerRanges where markerRange.length > 0 {
                attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: markerRange)
                hideSyntaxIfNeeded(
                    markerRange,
                    in: attributed,
                    text: text,
                    baseFont: baseFont,
                    syntaxMode: syntaxMode,
                    revealedRange: revealedRange
                )
            }
        }
    }

    private func styleHorizontalRules(
        in attributed: NSMutableAttributedString,
        text: NSString,
        lineRanges: [NSRange],
        protectedRanges: [NSRange],
        baseFont: UIFont
    ) {
        for lineRange in lineRanges {
            let contentRange = trimmedLineRange(from: lineRange, in: text)
            guard contentRange.length > 0 else {
                continue
            }
            guard protectedRanges.contains(where: { NSIntersectionRange($0, contentRange).length > 0 }) == false else {
                continue
            }

            let line = text.substring(with: contentRange)
            guard isHorizontalRule(line) else {
                continue
            }

            attributed.addAttributes(
                [
                    .foregroundColor: UIColor.tertiaryLabel,
                    .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
                ],
                range: contentRange
            )
        }
    }

    private func styleLinks(
        in attributed: NSMutableAttributedString,
        text: NSString,
        protectedRanges: [NSRange],
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        let regex = regex(for: #"\[([^\]]+)\]\(([^)]+)\)"#)
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 3
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard
                protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false,
                isEscaped(location: fullMatch.location, in: text as String) == false,
                isImageSyntaxStart(fullMatch.location, in: text as String) == false
            else {
                return
            }

            let titleRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            attributed.addAttributes(
                [
                    .foregroundColor: UIColor.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: titleRange
            )

            let hiddenRanges = [
                NSRange(location: fullMatch.location, length: 1),
                NSRange(location: NSMaxRange(titleRange), length: 2),
                urlRange,
                NSRange(location: NSMaxRange(fullMatch) - 1, length: 1)
            ]
            for hiddenRange in hiddenRanges {
                attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: hiddenRange)
                hideSyntaxIfNeeded(
                    hiddenRange,
                    in: attributed,
                    text: text,
                    baseFont: attributed.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 16),
                    syntaxMode: syntaxMode,
                    revealedRange: revealedRange
                )
            }
        }
    }

    private func styleImages(
        in attributed: NSMutableAttributedString,
        text: NSString,
        protectedRanges: [NSRange],
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        let regex = regex(for: #"!\[([^\]]*)\]\(([^)]+)\)"#)
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 3
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard
                protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false,
                isEscaped(location: fullMatch.location, in: text as String) == false
            else {
                return
            }

            let altTextRange = match.range(at: 1)
            let sourceRange = match.range(at: 2)
            let imageFont = transformedFont(baseFont, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: baseFont.pointSize)
            attributed.addAttributes(
                [
                    .font: imageFont,
                    .foregroundColor: UIColor.secondaryLabel
                ],
                range: altTextRange
            )

            let hiddenRanges = [
                NSRange(location: fullMatch.location, length: 2),
                NSRange(location: NSMaxRange(altTextRange), length: 2),
                sourceRange,
                NSRange(location: NSMaxRange(fullMatch) - 1, length: 1)
            ]
            for hiddenRange in hiddenRanges {
                attributed.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: hiddenRange)
                hideSyntaxIfNeeded(
                    hiddenRange,
                    in: attributed,
                    text: text,
                    baseFont: baseFont,
                    syntaxMode: syntaxMode,
                    revealedRange: revealedRange
                )
            }
        }
    }

    private func lineRanges(in text: NSString) -> [NSRange] {
        guard text.length > 0 else {
            return []
        }

        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = NSMaxRange(range)
        }
        return ranges
    }

    private func trimmedLineRange(
        from lineRange: NSRange,
        in text: NSString
    ) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let scalar = text.character(at: lineRange.location + length - 1)
            guard scalar == 10 || scalar == 13 else {
                break
            }
            length -= 1
        }

        return NSRange(location: lineRange.location, length: length)
    }

    private func indentedCodeBlockRanges(
        in text: NSString,
        lineRanges: [NSRange]
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        var currentBlock: NSRange?

        for lineRange in lineRanges {
            let trimmedRange = trimmedLineRange(from: lineRange, in: text)
            let line = text.substring(with: trimmedRange)

            if isIndentedCodeBlockLine(line) {
                currentBlock = currentBlock.map { NSUnionRange($0, lineRange) } ?? lineRange
            } else {
                if let block = currentBlock {
                    ranges.append(block)
                    currentBlock = nil
                }
            }
        }

        if let block = currentBlock {
            ranges.append(block)
        }

        return ranges
    }

    private func fencedCodeBlockMatches(
        in text: NSString,
        lineRanges: [NSRange]
    ) -> [FencedCodeBlockMatch] {
        var matches: [FencedCodeBlockMatch] = []
        var openingLineRange: NSRange?
        var openingFenceRange: NSRange?

        for lineRange in lineRanges {
            let trimmedRange = trimmedLineRange(from: lineRange, in: text)
            let line = text.substring(with: trimmedRange)

            guard let fenceRange = fencedCodeDelimiterRange(in: line) else {
                continue
            }

            let fenceLocation = trimmedRange.location + fenceRange.location
            guard isEscaped(location: fenceLocation, in: text as String) == false else {
                continue
            }

            let absoluteFenceRange = NSRange(
                location: fenceLocation,
                length: fenceRange.length
            )

            if let openingRange = openingLineRange, let openingFence = openingFenceRange {
                let fullRange = NSUnionRange(openingRange, lineRange)
                let contentStart = NSMaxRange(openingRange)
                let contentEnd = lineRange.location
                let contentRange = NSRange(
                    location: contentStart,
                    length: max(0, contentEnd - contentStart)
                )
                matches.append(
                    FencedCodeBlockMatch(
                        fullRange: fullRange,
                        contentRange: contentRange,
                        openingFenceRange: openingFence,
                        closingFenceRange: absoluteFenceRange
                    )
                )
                openingLineRange = nil
                openingFenceRange = nil
            } else {
                openingLineRange = lineRange
                openingFenceRange = absoluteFenceRange
            }
        }

        if let openingRange = openingLineRange, let openingFence = openingFenceRange {
            let contentStart = NSMaxRange(openingRange)
            let contentRange = NSRange(
                location: contentStart,
                length: max(0, text.length - contentStart)
            )
            matches.append(
                FencedCodeBlockMatch(
                    fullRange: NSRange(location: openingRange.location, length: text.length - openingRange.location),
                    contentRange: contentRange,
                    openingFenceRange: openingFence,
                    closingFenceRange: nil
                )
            )
        }

        return matches
    }


    private func isIndentedCodeBlockLine(_ line: String) -> Bool {
        if line.hasPrefix("\t") {
            return isListItemLine(String(line.dropFirst())) == false
        }

        if line.hasPrefix("    ") {
            return isListItemLine(String(line.dropFirst(4))) == false
        }

        return false
    }

    private func fencedCodeDelimiterRange(in line: String) -> NSRange? {
        let nsLine = line as NSString
        let pattern = #"^[ \t]{0,3}```[^\n\r`]*$"#
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex(for: pattern).firstMatch(in: line, options: [], range: range) else {
            return nil
        }

        return match.range(at: 0)
    }

    private func isListItemLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else {
            return false
        }

        if let first = trimmed.first, ["-", "*", "+"].contains(first) {
            return trimmed.dropFirst().first?.isWhitespace == true
        }

        var digits = ""
        for character in trimmed {
            if character.isNumber {
                digits.append(character)
                continue
            }

            if character == ".", digits.isEmpty == false {
                return trimmed.dropFirst(digits.count + 1).first?.isWhitespace == true
            }

            break
        }

        return false
    }

    private func setextHeadingMatches(
        in text: NSString,
        lineRanges: [NSRange],
        protectedRanges: [NSRange]
    ) -> [SetextHeadingMatch] {
        guard lineRanges.count >= 2 else {
            return []
        }

        var matches: [SetextHeadingMatch] = []
        for index in 1..<lineRanges.count {
            let contentLineRange = trimmedLineRange(from: lineRanges[index - 1], in: text)
            let underlineLineRange = trimmedLineRange(from: lineRanges[index], in: text)
            guard
                contentLineRange.length > 0,
                underlineLineRange.length > 0,
                protectedRanges.contains(where: { NSIntersectionRange($0, contentLineRange).length > 0 || NSIntersectionRange($0, underlineLineRange).length > 0 }) == false
            else {
                continue
            }

            let contentLine = text.substring(with: contentLineRange)
            let underlineLine = text.substring(with: underlineLineRange)
            let normalizedUnderline = underlineLine.removingMarkdownWhitespace()

            guard
                contentLine.trimmingCharacters(in: .whitespaces).isEmpty == false,
                isSetextUnderline(normalizedUnderline)
            else {
                continue
            }

            let level = normalizedUnderline.first == "=" ? 1 : 2
            matches.append(
                SetextHeadingMatch(
                    contentRange: contentLineRange,
                    underlineRange: underlineLineRange,
                    level: level
                )
            )
        }

        return matches
    }

    private func isSetextUnderline(_ line: String) -> Bool {
        guard line.count >= 3 else {
            return false
        }

        if Set(line).count != 1 {
            return false
        }

        return line.first == "=" || line.first == "-"
    }

    private func inlineCodeMatches(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [CodeSpanMatch] {
        let utf16 = Array(text.utf16)
        var matches: [CodeSpanMatch] = []
        var index = 0

        while index < utf16.count {
            guard utf16[index] == 96 else {
                index += 1
                continue
            }

            let delimiterStart = index
            while index < utf16.count, utf16[index] == 96 {
                index += 1
            }
            let delimiterLength = index - delimiterStart
            guard isEscaped(location: delimiterStart, in: text) == false else {
                continue
            }

            var searchIndex = index
            var foundMatch: CodeSpanMatch?
            while searchIndex < utf16.count {
                if utf16[searchIndex] == 10 || utf16[searchIndex] == 13 {
                    break
                }

                guard utf16[searchIndex] == 96 else {
                    searchIndex += 1
                    continue
                }

                let closingStart = searchIndex
                while searchIndex < utf16.count, utf16[searchIndex] == 96 {
                    searchIndex += 1
                }
                let closingLength = searchIndex - closingStart
                guard closingLength == delimiterLength else {
                    continue
                }

                let fullRange = NSRange(location: delimiterStart, length: searchIndex - delimiterStart)
                guard protectedRanges.contains(where: { NSIntersectionRange($0, fullRange).length > 0 }) == false else {
                    foundMatch = nil
                    break
                }

                let contentRange = NSRange(
                    location: delimiterStart + delimiterLength,
                    length: closingStart - (delimiterStart + delimiterLength)
                )
                foundMatch = CodeSpanMatch(
                    fullRange: fullRange,
                    contentRange: contentRange,
                    delimiterLength: delimiterLength
                )
                break
            }

            if let foundMatch {
                matches.append(foundMatch)
                index = NSMaxRange(foundMatch.fullRange)
            }
        }

        return matches
    }

    private func imageRanges(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [NSRange] {
        let regex = regex(for: #"!\[([^\]]*)\]\(([^)]+)\)"#)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: range)
            .map(\.range)
            .filter { matchRange in
                protectedRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) == false
                    && isEscaped(location: matchRange.location, in: text) == false
            }
    }

    private func inlineRanges(
        matching patterns: [String],
        in text: String,
        protectedRanges: [NSRange]
    ) -> [NSRange] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return patterns.flatMap { pattern in
            regex(for: pattern).matches(in: text, options: [], range: range)
                .map(\.range)
                .filter { matchRange in
                    protectedRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) == false
                        && isEscaped(location: matchRange.location, in: text) == false
                }
        }
    }

    private func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard ranges.isEmpty == false else {
            return []
        }

        let sortedRanges = ranges.sorted { lhs, rhs in
            if lhs.location == rhs.location {
                return lhs.length < rhs.length
            }

            return lhs.location < rhs.location
        }

        var merged: [NSRange] = [sortedRanges[0]]
        for range in sortedRanges.dropFirst() {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if NSIntersectionRange(last, range).length > 0 || NSMaxRange(last) == range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.removingMarkdownWhitespace()
        guard compact.count >= 3 else {
            return false
        }

        let distinctCharacters = Set(compact)
        guard distinctCharacters.count == 1, let marker = compact.first else {
            return false
        }

        return marker == "*" || marker == "-" || marker == "_"
    }

    private func isEscaped(
        location: Int,
        in text: String
    ) -> Bool {
        guard location > 0 else {
            return false
        }

        let utf16 = Array(text.utf16)
        var index = location - 1
        var backslashCount = 0
        while index >= 0, utf16[index] == 92 {
            backslashCount += 1
            index -= 1
        }

        return backslashCount.isMultiple(of: 2) == false
    }

    private func isImageSyntaxStart(
        _ location: Int,
        in text: String
    ) -> Bool {
        guard location > 0 else {
            return false
        }

        let utf16 = Array(text.utf16)
        return utf16[location - 1] == 33 && isEscaped(location: location - 1, in: text) == false
    }

    private func baseAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: UIColor.label
        ]
    }

    private func applyFontTransform(
        in attributed: NSMutableAttributedString,
        range: NSRange,
        transform: (UIFont) -> UIFont,
        baseFont: UIFont
    ) {
        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let currentFont = (value as? UIFont) ?? baseFont
            attributed.addAttribute(.font, value: transform(currentFont), range: subrange)
        }
    }

    private func hideSyntaxIfNeeded(
        _ range: NSRange,
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        guard range.length > 0 else {
            return
        }

        guard syntaxMode == .hiddenOutsideCurrentLine else {
            return
        }

        if let revealedRange, NSIntersectionRange(revealedRange, range).length > 0 {
            return
        }

        attributed.addAttributes(
            [
                .foregroundColor: UIColor.clear,
                .font: baseFont.withSize(0.1)
            ],
            range: range
        )

        let width = (text.substring(with: range) as NSString).size(
            withAttributes: [.font: baseFont]
        ).width
        let kerningRange = NSRange(location: NSMaxRange(range) - 1, length: 1)
        attributed.addAttribute(.kern, value: -width, range: kerningRange)
    }

    private func hideRange(
        _ range: NSRange,
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont
    ) {
        guard range.length > 0 else {
            return
        }

        attributed.addAttributes(
            [
                .foregroundColor: UIColor.clear,
                .font: baseFont.withSize(0.1)
            ],
            range: range
        )

        let width = (text.substring(with: range) as NSString).size(
            withAttributes: [.font: baseFont]
        ).width
        let kerningRange = NSRange(location: NSMaxRange(range) - 1, length: 1)
        attributed.addAttribute(.kern, value: -width, range: kerningRange)
    }

    private func regex(
        for pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("Invalid markdown styling regex: \(pattern)")
        }
    }
}

private func transformedFont(
    _ font: UIFont,
    addingSingle trait: UIFontDescriptor.SymbolicTraits,
    size: CGFloat? = nil
) -> UIFont? {
    transformedFont(font, adding: trait, size: size)
}

private func transformedFont(
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

private extension String {
    func removingMarkdownWhitespace() -> String {
        filter { $0.isWhitespace == false }
    }

    func measuredWidth(using font: UIFont) -> CGFloat {
        (self as NSString).size(withAttributes: [.font: font]).width
    }
}
