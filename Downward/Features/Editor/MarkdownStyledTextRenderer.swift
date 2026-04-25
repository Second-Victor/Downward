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
        let styleApplicator = MarkdownSyntaxStyleApplicator(
            baseFont: configuration.baseFont,
            resolvedTheme: configuration.resolvedTheme,
            syntaxMode: configuration.syntaxMode,
            revealedRange: configuration.revealedRange
        )
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: styleApplicator.baseAttributes
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
        let inlineStyleSpans = scanner.inlineStyleSpans(
            in: text,
            protectedRanges: emphasisProtectedRanges
        )

        styleIndentedCodeBlocks(
            in: attributed,
            text: nsText,
            ranges: indentedCodeBlockRanges,
            styleApplicator: styleApplicator
        )
        styleFencedCodeBlocks(
            matches: fencedCodeBlockMatches,
            in: attributed,
            styleApplicator: styleApplicator
        )
        styleSetextHeadings(
            matches: setextMatches,
            in: attributed,
            styleApplicator: styleApplicator
        )
        styleHeadings(
            in: attributed,
            text: nsText,
            styleApplicator: styleApplicator,
            protectedRanges: codeBlockRanges
        )
        styleHorizontalRules(
            in: attributed,
            text: nsText,
            lineRanges: lineRanges,
            protectedRanges: codeBlockRanges + setextUnderlineRanges,
            styleApplicator: styleApplicator
        )
        styleBlockquotes(
            in: attributed,
            text: nsText,
            lineRanges: lineRanges,
            styleApplicator: styleApplicator,
            protectedRanges: codeBlockRanges
        )
        styleLists(
            in: attributed,
            text: nsText,
            styleApplicator: styleApplicator,
            protectedRanges: codeBlockRanges
        )
        styleInlineCode(
            matches: codeSpanMatches,
            in: attributed,
            styleApplicator: styleApplicator
        )
        styleDelimitedInlineSpans(
            inlineStyleSpans,
            in: attributed,
            styleApplicator: styleApplicator
        )
        styleImages(
            in: attributed,
            text: nsText,
            protectedRanges: codeBlockRanges + codeSpanRanges,
            styleApplicator: styleApplicator
        )
        styleLinks(
            in: attributed,
            text: nsText,
            protectedRanges: codeBlockRanges + codeSpanRanges + imageRanges,
            styleApplicator: styleApplicator
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
        styleApplicator: MarkdownSyntaxStyleApplicator,
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
            styleApplicator.applyATXHeading(
                contentRange: contentRange,
                markerRange: markerRange,
                spacerRange: spacerRange,
                level: markerRange.length,
                in: attributed
            )
        }
    }

    private func styleSetextHeadings(
        matches: [SetextHeadingMatch],
        in attributed: NSMutableAttributedString,
        styleApplicator: MarkdownSyntaxStyleApplicator
    ) {
        for match in matches {
            styleApplicator.applySetextHeading(
                contentRange: match.contentRange,
                underlineRange: match.underlineRange,
                level: match.level,
                in: attributed
            )
        }
    }

    private func styleBlockquotes(
        in attributed: NSMutableAttributedString,
        text: NSString,
        lineRanges: [NSRange],
        styleApplicator: MarkdownSyntaxStyleApplicator,
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

            styleApplicator.applyBlockquote(
                lineRange: lineRange,
                leadingWhitespaceRange: leadingWhitespaceRange,
                markerRange: markerRange,
                depth: depth,
                groupID: groupID,
                text: text,
                in: attributed
            )
        }
    }

    private func styleLists(
        in attributed: NSMutableAttributedString,
        text: NSString,
        styleApplicator: MarkdownSyntaxStyleApplicator,
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
                styleApplicator.applyList(
                    fullMatch: fullMatch,
                    leadingWhitespaceRange: leadingWhitespaceRange,
                    spacerRange: spacerRange,
                    markerRange: markerRange,
                    text: text,
                    in: attributed
                )
            }
        }
    }

    private func styleIndentedCodeBlocks(
        in attributed: NSMutableAttributedString,
        text: NSString,
        ranges: [NSRange],
        styleApplicator: MarkdownSyntaxStyleApplicator
    ) {
        guard ranges.isEmpty == false else {
            return
        }

        for range in ranges {
            styleApplicator.applyIndentedCodeBlock(range: range, in: attributed)
        }
    }

    private func styleFencedCodeBlocks(
        matches: [MarkdownFencedCodeBlock],
        in attributed: NSMutableAttributedString,
        styleApplicator: MarkdownSyntaxStyleApplicator
    ) {
        for match in matches {
            styleApplicator.applyFencedCodeBlock(match, in: attributed)
        }
    }

    private func styleInlineCode(
        matches: [MarkdownCodeSpan],
        in attributed: NSMutableAttributedString,
        styleApplicator: MarkdownSyntaxStyleApplicator
    ) {
        for match in matches {
            styleApplicator.applyInlineCode(match, in: attributed)
        }
    }

    private func styleDelimitedInlineSpans(
        _ spans: [MarkdownDelimitedInlineSpan],
        in attributed: NSMutableAttributedString,
        styleApplicator: MarkdownSyntaxStyleApplicator
    ) {
        for span in spans {
            styleApplicator.applyDelimitedInlineSpan(span, in: attributed)
        }
    }

    private func styleHorizontalRules(
        in attributed: NSMutableAttributedString,
        text: NSString,
        lineRanges: [NSRange],
        protectedRanges: [NSRange],
        styleApplicator: MarkdownSyntaxStyleApplicator
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

            styleApplicator.applyHorizontalRule(range: contentRange, in: attributed)
        }
    }

    private func styleLinks(
        in attributed: NSMutableAttributedString,
        text: NSString,
        protectedRanges: [NSRange],
        styleApplicator: MarkdownSyntaxStyleApplicator
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
            let hiddenRanges = [
                NSRange(location: fullMatch.location, length: 1),
                NSRange(location: NSMaxRange(titleRange), length: 2),
                urlRange,
                NSRange(location: NSMaxRange(fullMatch) - 1, length: 1)
            ]
            styleApplicator.applyLink(
                titleRange: titleRange,
                hiddenRanges: hiddenRanges,
                in: attributed
            )
        }
    }

    private func styleImages(
        in attributed: NSMutableAttributedString,
        text: NSString,
        protectedRanges: [NSRange],
        styleApplicator: MarkdownSyntaxStyleApplicator
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
            let hiddenRanges = [
                NSRange(location: fullMatch.location, length: 2),
                NSRange(location: NSMaxRange(altTextRange), length: 2),
                sourceRange,
                NSRange(location: NSMaxRange(fullMatch) - 1, length: 1)
            ]
            styleApplicator.applyImage(
                altTextRange: altTextRange,
                hiddenRanges: hiddenRanges,
                in: attributed
            )
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

private func shift(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
}

private extension String {
    func removingMarkdownWhitespace() -> String {
        filter { $0.isWhitespace == false }
    }
}
