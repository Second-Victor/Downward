import Foundation
import UIKit

struct MarkdownStyledTextRenderer {
    private static let regexCache = NSCache<NSString, NSRegularExpression>()
    private let scanner = MarkdownSyntaxScanner()

    struct Configuration: Equatable {
        let text: String
        let baseFont: UIFont
        let resolvedTheme: ResolvedEditorTheme
        let syntaxMode: MarkdownSyntaxMode
        let revealedRange: NSRange?

        init(
            text: String,
            baseFont: UIFont,
            resolvedTheme: ResolvedEditorTheme = .default,
            syntaxMode: MarkdownSyntaxMode,
            revealedRange: NSRange?
        ) {
            self.text = text
            self.baseFont = baseFont
            self.resolvedTheme = resolvedTheme
            self.syntaxMode = syntaxMode
            self.revealedRange = revealedRange
        }
    }

    private struct SetextHeadingMatch {
        let contentRange: NSRange
        let underlineRange: NSRange
        let level: Int
    }

    func render(configuration: Configuration) -> NSAttributedString {
        let text = configuration.text
        let nsText = text as NSString
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes(font: configuration.baseFont, resolvedTheme: configuration.resolvedTheme)
        )

        let syntaxScan = scanner.scan(text)
        let lineRanges = syntaxScan.lineRanges
        let indentedCodeBlockRanges = syntaxScan.indentedCodeBlockRanges
        let fencedCodeBlockMatches = syntaxScan.fencedCodeBlocks
        let codeBlockRanges = syntaxScan.codeBlockRanges
        let setextMatches = setextHeadingMatches(
            in: nsText,
            lineRanges: lineRanges,
            protectedRanges: codeBlockRanges
        )
        let setextUnderlineRanges = setextMatches.map(\.underlineRange)
        let codeSpanMatches = syntaxScan.inlineCodeSpans
        let codeSpanRanges = codeSpanMatches.map(\.fullRange)
        let imageRanges = syntaxScan.imageRanges
        let emphasisProtectedRanges = codeBlockRanges + codeSpanRanges + imageRanges
        let boldItalicRanges = scanner.inlineRanges(
            matching: [
                #"(?<!\*)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*(?!\*)"#,
                #"(?<!_)___(?=\S)(.+?)(?<=\S)___(?!_)"#
            ],
            in: text,
            protectedRanges: emphasisProtectedRanges
        )
        let nestedBoldItalicRanges = scanner.inlineRanges(
            matching: [
                #"(?<!_)__(\*)(?=\S)(.+?)(?<=\S)\1__(?!_)"#,
                #"(?<!\*)\*\*(_)(?=\S)(.+?)(?<=\S)\1\*\*(?!\*)"#,
                #"(?<!_)\_(\*\*)(?=\S)(.+?)(?<=\S)\1_(?!_)"#,
                #"(?<!\*)\*(__)(?=\S)(.+?)(?<=\S)\1\*(?!\*)"#
            ],
            in: text,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges
        )
        let boldRanges = scanner.inlineRanges(
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
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme
        )
        styleFencedCodeBlocks(
            matches: fencedCodeBlockMatches,
            in: attributed,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleSetextHeadings(
            matches: setextMatches,
            in: attributed,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleHeadings(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            protectedRanges: codeBlockRanges
        )
        styleHorizontalRules(
            in: attributed,
            text: nsText,
            lineRanges: lineRanges,
            protectedRanges: codeBlockRanges + setextUnderlineRanges,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleBlockquotes(
            in: attributed,
            text: nsText,
            lineRanges: lineRanges,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            protectedRanges: codeBlockRanges
        )
        styleLists(
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            protectedRanges: codeBlockRanges
        )
        styleInlineCode(
            matches: codeSpanMatches,
            in: attributed,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!\*)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!_)___(?=\S)(.+?)(?<=\S)___(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!_)__(\*)(?=\S)(.+?)(?<=\S)\1__(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!\*)\*\*(_)(?=\S)(.+?)(?<=\S)\1\*\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!_)\_(\*\*)(?=\S)(.+?)(?<=\S)\1_(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleNestedDelimitedInlinePattern(
            pattern: #"(?<!\*)\*(__)(?=\S)(.+?)(?<=\S)\1\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: [.traitBold, .traitItalic])
                    ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitBold) ?? UIFont.boldSystemFont(ofSize: font.pointSize)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!_)__(?=\S)(.+?)(?<=\S)__(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitBold) ?? UIFont.boldSystemFont(ofSize: font.pointSize)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!\*)\*(?=\S)(.+?)(?<=\S)\*(?!\*)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges + boldRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: font.pointSize)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleDelimitedInlinePattern(
            pattern: #"(?<!_)_(?=\S)(.+?)(?<=\S)_(?!_)"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges + boldItalicRanges + nestedBoldItalicRanges + boldRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in
                transformedFont(font, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: font.pointSize)
            },
            additionalContentAttributes: [.foregroundColor: configuration.resolvedTheme.emphasisText]
        )
        styleDelimitedInlinePattern(
            pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#,
            in: attributed,
            text: nsText,
            baseFont: configuration.baseFont,
            protectedRanges: emphasisProtectedRanges,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange,
            contentTransform: { font in font },
            additionalContentAttributes: [
                .foregroundColor: configuration.resolvedTheme.strikethroughText,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        styleImages(
            in: attributed,
            text: nsText,
            protectedRanges: codeBlockRanges + codeSpanRanges,
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        styleLinks(
            in: attributed,
            text: nsText,
            protectedRanges: codeBlockRanges + codeSpanRanges + imageRanges,
            resolvedTheme: configuration.resolvedTheme,
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

    func updateHiddenSyntaxVisibility(
        in textStorage: NSTextStorage,
        previousRevealedRange: NSRange?,
        revealedRange: NSRange?
    ) {
        let affectedRanges = scanner.mergedRanges(
            [previousRevealedRange, revealedRange]
                .compactMap { clampedRange($0, length: textStorage.length) }
        )
        guard affectedRanges.isEmpty == false else {
            return
        }

        // Reuse the stored visibility rule so caret-line updates preserve each
        // syntax token's contract without requiring a full rerender.
        var syntaxRanges: [NSRange] = []
        var syntaxVisibilityRules: [MarkdownSyntaxVisibilityRule] = []
        for affectedRange in affectedRanges {
            textStorage.enumerateAttribute(.markdownSyntaxToken, in: affectedRange) { value, range, _ in
                guard
                    let rawValue = value as? Int,
                    let visibilityRule = MarkdownSyntaxVisibilityRule(rawValue: rawValue)
                else {
                    return
                }

                syntaxRanges.append(range)
                syntaxVisibilityRules.append(visibilityRule)
            }
        }

        guard syntaxRanges.isEmpty == false else {
            return
        }

        var changedRanges: [NSRange] = []
        textStorage.beginEditing()
        for (syntaxRange, visibilityRule) in zip(syntaxRanges, syntaxVisibilityRules) {
            let shouldHideSyntax = MarkdownSyntaxVisibilityPolicy(
                syntaxMode: .hiddenOutsideCurrentLine,
                revealedRange: revealedRange
            )
            .shouldHideSyntax(in: syntaxRange, rule: visibilityRule)
            let currentlyHidden = (textStorage.attribute(
                .markdownHiddenSyntax,
                at: syntaxRange.location,
                longestEffectiveRange: nil,
                in: syntaxRange
            ) as? Bool) == true
            guard currentlyHidden != shouldHideSyntax else {
                continue
            }

            if shouldHideSyntax {
                textStorage.addAttribute(.markdownHiddenSyntax, value: true, range: syntaxRange)
            } else {
                textStorage.removeAttribute(.markdownHiddenSyntax, range: syntaxRange)
            }
            changedRanges.append(syntaxRange)
        }
        textStorage.endEditing()

        let invalidationRanges = scanner.mergedRanges(changedRanges)
        for affectedRange in invalidationRanges {
            for layoutManager in textStorage.layoutManagers {
                layoutManager.invalidateLayout(forCharacterRange: affectedRange, actualCharacterRange: nil)
                layoutManager.invalidateDisplay(forCharacterRange: affectedRange)
            }
        }
    }

    private func styleHeadings(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
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
                scanner.isEscaped(location: fullMatch.location, in: text) == false
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
                    .foregroundColor: resolvedTheme.headingText
                ],
                range: contentRange
            )
            attributed.addAttribute(
                .foregroundColor,
                value: resolvedTheme.syntaxMarkerText,
                range: markerRange
            )

            applySyntaxVisibility(
                markerRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
            applySyntaxVisibility(
                spacerRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleSetextHeadings(
        matches: [SetextHeadingMatch],
        in attributed: NSMutableAttributedString,
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
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
                    .foregroundColor: resolvedTheme.headingText
                ],
                range: match.contentRange
            )
            attributed.addAttribute(
                .foregroundColor,
                value: resolvedTheme.syntaxMarkerText,
                range: match.underlineRange
            )
            applySyntaxVisibility(
                match.underlineRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleBlockquotes(
        in attributed: NSMutableAttributedString,
        text: NSString,
        lineRanges: [NSRange],
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?,
        protectedRanges: [NSRange]
    ) {
        let regex = regex(for: #"^([ \t]{0,3})((?:>[ \t]?)+)(.*)$"#)
        var currentGroupID: Int?
        var nextGroupID = 0

        for lineRange in lineRanges {
            let trimmedRange = scanner.trimmedLineRange(from: lineRange, in: text)
            guard trimmedRange.length > 0 else {
                currentGroupID = nil
                continue
            }

            let line = text.substring(with: trimmedRange)
            let matchRange = NSRange(location: 0, length: (line as NSString).length)
            guard let match = regex.firstMatch(in: line, options: [], range: matchRange) else {
                currentGroupID = nil
                continue
            }

            let fullMatch = NSRange(location: lineRange.location, length: trimmedRange.length)
            guard protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false else {
                currentGroupID = nil
                continue
            }

            if currentGroupID == nil {
                nextGroupID += 1
                currentGroupID = nextGroupID
            }

            let leadingWhitespaceRange = shift(match.range(at: 1), by: lineRange.location)
            let markerRange = shift(match.range(at: 2), by: lineRange.location)
            let depth = text.substring(with: markerRange).reduce(into: 0) { count, character in
                if character == ">" {
                    count += 1
                }
            }
            guard depth > 0, let groupID = currentGroupID else {
                currentGroupID = nil
                continue
            }

            attributed.addAttribute(.markdownBlockquoteDepth, value: depth, range: lineRange)
            attributed.addAttribute(.markdownBlockquoteGroupID, value: groupID, range: lineRange)
            attributed.addAttribute(.foregroundColor, value: resolvedTheme.blockquoteText, range: lineRange)
            attributed.addAttribute(.foregroundColor, value: resolvedTheme.subtleSyntaxMarkerText, range: markerRange)

            let paragraphStyle = NSMutableParagraphStyle()
            let leadingWidth = text.substring(with: leadingWhitespaceRange).measuredWidth(using: baseFont)
            let headIndent = leadingWidth + CGFloat(depth) * 12 + 6
            paragraphStyle.firstLineHeadIndent = headIndent
            paragraphStyle.headIndent = headIndent
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

            applySyntaxVisibility(
                markerRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleLists(
        in attributed: NSMutableAttributedString,
        text: NSString,
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
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
                attributed.addAttribute(.foregroundColor, value: resolvedTheme.syntaxMarkerText, range: markerRange)

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
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme
    ) {
        guard ranges.isEmpty == false else {
            return
        }

        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
        for range in ranges {
            attributed.addAttributes(
                [
                    .font: codeFont,
                    .foregroundColor: resolvedTheme.codeBlockText,
                    .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.block.rawValue
                ],
                range: range
            )
        }
    }

    private func styleFencedCodeBlocks(
        matches: [MarkdownFencedCodeBlock],
        in attributed: NSMutableAttributedString,
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
        for match in matches {
            if match.contentRange.length > 0 {
                attributed.addAttributes(
                    [
                        .font: codeFont,
                        .foregroundColor: resolvedTheme.codeBlockText,
                        .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.block.rawValue
                    ],
                    range: match.contentRange
                )
            }

            applySyntaxVisibility(
                match.openingFenceRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )

            if let closingFenceRange = match.closingFenceRange {
                applySyntaxVisibility(
                    closingFenceRange,
                    rule: .followsMode,
                    in: attributed,
                    syntaxMode: syntaxMode,
                    revealedRange: revealedRange
                )
            }
        }
    }

    private func styleInlineCode(
        matches: [MarkdownCodeSpan],
        in attributed: NSMutableAttributedString,
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
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
                    .foregroundColor: resolvedTheme.inlineCodeText,
                    .markdownCodeBackgroundKind: MarkdownCodeBackgroundKind.inline.rawValue
                ],
                range: match.contentRange
            )
            applySyntaxVisibility(
                openMarkerRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
            applySyntaxVisibility(
                closeMarkerRange,
                rule: .followsMode,
                in: attributed,
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
        resolvedTheme: ResolvedEditorTheme,
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
                scanner.isEscaped(location: fullMatch.location, in: text) == false
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

            attributed.addAttribute(.foregroundColor, value: resolvedTheme.syntaxMarkerText, range: leadingMarkerRange)
            attributed.addAttribute(.foregroundColor, value: resolvedTheme.syntaxMarkerText, range: trailingMarkerRange)
            applySyntaxVisibility(
                leadingMarkerRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
            applySyntaxVisibility(
                trailingMarkerRange,
                rule: .followsMode,
                in: attributed,
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
        resolvedTheme: ResolvedEditorTheme,
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
                match.numberOfRanges == 3
            else {
                return
            }

            let fullMatch = match.range(at: 0)
            guard
                protectedRanges.contains(where: { NSIntersectionRange($0, fullMatch).length > 0 }) == false,
                scanner.isEscaped(location: fullMatch.location, in: text) == false
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
            for (key, value) in additionalContentAttributes {
                attributed.addAttribute(key, value: value, range: contentRange)
            }

            let markerRanges = [leadingOuterRange, leadingInnerRange, trailingInnerRange, trailingOuterRange]
            for markerRange in markerRanges where markerRange.length > 0 {
                attributed.addAttribute(.foregroundColor, value: resolvedTheme.syntaxMarkerText, range: markerRange)
                applySyntaxVisibility(
                    markerRange,
                    rule: .followsMode,
                    in: attributed,
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
        baseFont: UIFont,
        resolvedTheme: ResolvedEditorTheme,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        for lineRange in lineRanges {
            let contentRange = scanner.trimmedLineRange(from: lineRange, in: text)
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
                    .foregroundColor: resolvedTheme.horizontalRuleText,
                    .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
                    .markdownHorizontalRule: true
                ],
                range: contentRange
            )
            applySyntaxVisibility(
                contentRange,
                rule: .followsMode,
                in: attributed,
                syntaxMode: syntaxMode,
                revealedRange: revealedRange
            )
        }
    }

    private func styleLinks(
        in attributed: NSMutableAttributedString,
        text: NSString,
        protectedRanges: [NSRange],
        resolvedTheme: ResolvedEditorTheme,
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
                scanner.isEscaped(location: fullMatch.location, in: text) == false,
                isImageSyntaxStart(fullMatch.location, in: text) == false
            else {
                return
            }

            let titleRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            attributed.addAttributes(
                [
                    .foregroundColor: resolvedTheme.linkText,
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
                attributed.addAttribute(.foregroundColor, value: resolvedTheme.syntaxMarkerText, range: hiddenRange)
                applySyntaxVisibility(
                    hiddenRange,
                    rule: .followsMode,
                    in: attributed,
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
        resolvedTheme: ResolvedEditorTheme,
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
                scanner.isEscaped(location: fullMatch.location, in: text) == false
            else {
                return
            }

            let altTextRange = match.range(at: 1)
            let sourceRange = match.range(at: 2)
            let imageFont = transformedFont(baseFont, adding: .traitItalic) ?? UIFont.italicSystemFont(ofSize: baseFont.pointSize)
            attributed.addAttributes(
                [
                    .font: imageFont,
                    .foregroundColor: resolvedTheme.imageAltText
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
                attributed.addAttribute(.foregroundColor, value: resolvedTheme.subtleSyntaxMarkerText, range: hiddenRange)
                applySyntaxVisibility(
                    hiddenRange,
                    rule: .followsMode,
                    in: attributed,
                    syntaxMode: syntaxMode,
                    revealedRange: revealedRange
                )
            }
        }
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
            let contentLineRange = scanner.trimmedLineRange(from: lineRanges[index - 1], in: text)
            let underlineLineRange = scanner.trimmedLineRange(from: lineRanges[index], in: text)
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

    private func clampedRange(
        _ range: NSRange?,
        length: Int
    ) -> NSRange? {
        guard let range else {
            return nil
        }

        let location = min(max(range.location, 0), length)
        let upperBound = min(max(NSMaxRange(range), location), length)
        let clamped = NSRange(location: location, length: upperBound - location)
        return clamped.length > 0 ? clamped : nil
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

    private func isImageSyntaxStart(
        _ location: Int,
        in text: NSString
    ) -> Bool {
        guard location > 0 else {
            return false
        }

        return text.character(at: location - 1) == 33
            && scanner.isEscaped(location: location - 1, in: text) == false
    }

    private func baseAttributes(font: UIFont, resolvedTheme: ResolvedEditorTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: resolvedTheme.primaryText
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

    // Keep one visibility decision point so new markdown features do not guess
    // between mode-controlled syntax and syntax that should always stay hidden.
    private func applySyntaxVisibility(
        _ range: NSRange,
        rule: MarkdownSyntaxVisibilityRule,
        in attributed: NSMutableAttributedString,
        syntaxMode: MarkdownSyntaxMode,
        revealedRange: NSRange?
    ) {
        guard range.length > 0 else {
            return
        }

        attributed.addAttribute(.markdownSyntaxToken, value: rule.rawValue, range: range)

        let visibilityPolicy = MarkdownSyntaxVisibilityPolicy(
            syntaxMode: syntaxMode,
            revealedRange: revealedRange
        )
        if visibilityPolicy.shouldHideSyntax(in: range, rule: rule) {
            applyHiddenSyntaxAttributes(range, in: attributed)
        } else {
            attributed.removeAttribute(.markdownHiddenSyntax, range: range)
        }
    }

    private func applyHiddenSyntaxAttributes(
        _ range: NSRange,
        in attributed: NSMutableAttributedString
    ) {
        guard range.length > 0 else {
            return
        }

        attributed.addAttribute(.markdownHiddenSyntax, value: true, range: range)
        attributed.removeAttribute(.kern, range: range)
    }

    private func regex(
        for pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        let cacheKey = "\(options.rawValue)|\(pattern)" as NSString
        if let cachedRegex = Self.regexCache.object(forKey: cacheKey) {
            return cachedRegex
        }

        do {
            let compiledRegex = try NSRegularExpression(pattern: pattern, options: options)
            Self.regexCache.setObject(compiledRegex, forKey: cacheKey)
            return compiledRegex
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

private func shift(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
}

private extension String {
    func removingMarkdownWhitespace() -> String {
        filter { $0.isWhitespace == false }
    }

    func measuredWidth(using font: UIFont) -> CGFloat {
        (self as NSString).size(withAttributes: [.font: font]).width
    }
}
