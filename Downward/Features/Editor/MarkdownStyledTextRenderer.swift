import Foundation
import UIKit

struct MarkdownStyledTextRenderer {
    struct Configuration: Equatable {
        let text: String
        let baseFont: UIFont
        let syntaxMode: MarkdownSyntaxMode
        let revealedRange: NSRange?
    }

    func render(configuration: Configuration) -> NSAttributedString {
        let text = configuration.text
        let nsText = text as NSString
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes(font: configuration.baseFont)
        )
        let codeRanges = inlineCodeRanges(in: text)
        let boldItalicRanges = inlineRanges(
            matching: [
                #"(?<!\*)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*(?!\*)"#,
                #"(?<!_)___(?=\S)(.+?)(?<=\S)___(?!_)"#
            ],
            in: text
        )
        let boldRanges = inlineRanges(
            matching: [
                #"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#,
                #"(?<!_)__(?=\S)(.+?)(?<=\S)__(?!_)"#
            ],
            in: text
        )

        styleHeadings(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleBlockquotes(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleInlineCode(
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
            protectedRanges: codeRanges,
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
            protectedRanges: codeRanges,
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
            protectedRanges: codeRanges + boldItalicRanges,
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
            protectedRanges: codeRanges + boldItalicRanges,
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
            protectedRanges: codeRanges + boldItalicRanges + boldRanges,
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
            protectedRanges: codeRanges + boldItalicRanges + boldRanges,
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
            protectedRanges: codeRanges,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in font },
            additionalContentAttributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        styleLinks(
            in: attributed,
            text: nsText,
            protectedRanges: codeRanges,
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
        revealedRange: NSRange?
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

    private func styleBlockquotes(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
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

    private func styleInlineCode(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        let pattern = #"(?<!`)`([^`\n]+)`(?!`)"#
        let regex = regex(for: pattern)
        let fullRange = NSRange(location: 0, length: text.length)
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                match.numberOfRanges == 2
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            let contentRange = match.range(at: 1)
            let openMarkerRange = NSRange(location: fullMatch.location, length: 1)
            let closeMarkerRange = NSRange(location: NSMaxRange(fullMatch) - 1, length: 1)

            attributed.addAttributes(
                [
                    .font: codeFont,
                    .backgroundColor: UIColor.secondarySystemFill,
                    .foregroundColor: UIColor.label
                ],
                range: contentRange
            )
            attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: fullMatch)

            hideSyntaxIfNeeded(
                openMarkerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
            hideSyntaxIfNeeded(
                closeMarkerRange,
                in: attributed,
                text: text,
                baseFont: baseFont,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
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
            guard protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false else {
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
            guard protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false else {
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

    private func inlineCodeRanges(in text: String) -> [NSRange] {
        let regex = regex(for: #"(?<!`)`([^`\n]+)`(?!`)"#)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: range).map(\.range)
    }

    private func inlineRanges(
        matching patterns: [String],
        in text: String
    ) -> [NSRange] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return patterns.flatMap { pattern in
            regex(for: pattern).matches(in: text, options: [], range: range).map(\.range)
        }
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
