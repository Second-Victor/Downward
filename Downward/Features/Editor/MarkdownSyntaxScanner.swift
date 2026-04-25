import Foundation

nonisolated struct MarkdownSyntaxScan: Equatable, Sendable {
    let lineRanges: [NSRange]
    let indentedCodeBlockRanges: [NSRange]
    let fencedCodeBlocks: [MarkdownFencedCodeBlock]
    let codeBlockRanges: [NSRange]
    let inlineCodeSpans: [MarkdownCodeSpan]
    let imageRanges: [NSRange]
}

nonisolated struct MarkdownCodeSpan: Equatable, Sendable {
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterLength: Int
}

nonisolated enum MarkdownInlineStyleKind: Equatable, Sendable {
    case boldItalic
    case bold
    case italic
    case strikethrough
}

nonisolated struct MarkdownDelimitedInlineSpan: Equatable, Sendable {
    let style: MarkdownInlineStyleKind
    let fullRange: NSRange
    let contentRange: NSRange
    let markerRanges: [NSRange]
}

nonisolated struct MarkdownFencedCodeBlock: Equatable, Sendable {
    let fullRange: NSRange
    let contentRange: NSRange
    let openingFenceRange: NSRange
    let closingFenceRange: NSRange?
}

/// Recognizes markdown structure that protects ranges or drives later styling.
/// It deliberately has no UIKit, TextKit, or attributed-string dependencies.
nonisolated struct MarkdownSyntaxScanner {
    nonisolated(unsafe) private static let regexCache = NSCache<NSString, NSRegularExpression>()

    func scan(_ text: String) -> MarkdownSyntaxScan {
        let lineRanges = lineRanges(in: text)
        let indentedCodeBlockRanges = indentedCodeBlockRanges(in: text, lineRanges: lineRanges)
        let fencedCodeBlocks = fencedCodeBlocks(in: text, lineRanges: lineRanges)
        let codeBlockRanges = mergedRanges(
            indentedCodeBlockRanges + fencedCodeBlocks.map(\.fullRange)
        )
        let inlineCodeSpans = inlineCodeSpans(in: text, protectedRanges: codeBlockRanges)
        let imageRanges = imageRanges(
            in: text,
            protectedRanges: codeBlockRanges + inlineCodeSpans.map(\.fullRange)
        )

        return MarkdownSyntaxScan(
            lineRanges: lineRanges,
            indentedCodeBlockRanges: indentedCodeBlockRanges,
            fencedCodeBlocks: fencedCodeBlocks,
            codeBlockRanges: codeBlockRanges,
            inlineCodeSpans: inlineCodeSpans,
            imageRanges: imageRanges
        )
    }

    func lineRanges(in text: String) -> [NSRange] {
        lineRanges(in: text as NSString)
    }

    func indentedCodeBlockRanges(
        in text: String,
        lineRanges: [NSRange]
    ) -> [NSRange] {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        var currentBlock: NSRange?

        for lineRange in lineRanges {
            let trimmedRange = trimmedLineRange(from: lineRange, in: nsText)
            let line = nsText.substring(with: trimmedRange)

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

    func fencedCodeBlocks(
        in text: String,
        lineRanges: [NSRange]
    ) -> [MarkdownFencedCodeBlock] {
        let nsText = text as NSString
        var blocks: [MarkdownFencedCodeBlock] = []
        var openingLineRange: NSRange?
        var openingFenceRange: NSRange?

        for lineRange in lineRanges {
            let trimmedRange = trimmedLineRange(from: lineRange, in: nsText)
            let line = nsText.substring(with: trimmedRange)

            guard let fenceRange = fencedCodeDelimiterRange(in: line) else {
                continue
            }

            let fenceLocation = trimmedRange.location + fenceRange.location
            guard isEscaped(location: fenceLocation, in: nsText) == false else {
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
                blocks.append(
                    MarkdownFencedCodeBlock(
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
                length: max(0, nsText.length - contentStart)
            )
            blocks.append(
                MarkdownFencedCodeBlock(
                    fullRange: NSRange(location: openingRange.location, length: nsText.length - openingRange.location),
                    contentRange: contentRange,
                    openingFenceRange: openingFence,
                    closingFenceRange: nil
                )
            )
        }

        return blocks
    }

    func inlineCodeSpans(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [MarkdownCodeSpan] {
        let nsText = text as NSString
        var matches: [MarkdownCodeSpan] = []
        var index = 0

        while index < nsText.length {
            guard nsText.character(at: index) == 96 else {
                index += 1
                continue
            }

            let delimiterStart = index
            while index < nsText.length, nsText.character(at: index) == 96 {
                index += 1
            }
            let delimiterLength = index - delimiterStart
            guard isEscaped(location: delimiterStart, in: nsText) == false else {
                continue
            }

            var searchIndex = index
            var foundMatch: MarkdownCodeSpan?
            while searchIndex < nsText.length {
                let character = nsText.character(at: searchIndex)
                if character == 10 || character == 13 {
                    break
                }

                guard character == 96 else {
                    searchIndex += 1
                    continue
                }

                let closingStart = searchIndex
                while searchIndex < nsText.length, nsText.character(at: searchIndex) == 96 {
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
                foundMatch = MarkdownCodeSpan(
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

    func imageRanges(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [NSRange] {
        let regex = regex(for: #"!\[([^\]]*)\]\(([^)]+)\)"#)
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range)
            .map(\.range)
            .filter { matchRange in
                protectedRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) == false
                    && isEscaped(location: matchRange.location, in: nsText) == false
            }
    }

    func inlineRanges(
        matching patterns: [String],
        in text: String,
        protectedRanges: [NSRange]
    ) -> [NSRange] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return patterns.flatMap { pattern in
            regex(for: pattern).matches(in: text, options: [], range: range)
                .map(\.range)
                .filter { matchRange in
                    protectedRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) == false
                        && isEscaped(location: matchRange.location, in: nsText) == false
                }
        }
    }

    func inlineStyleSpans(
        in text: String,
        protectedRanges: [NSRange]
    ) -> [MarkdownDelimitedInlineSpan] {
        let boldItalicSpans = delimitedInlineSpans(
            matching: [
                #"(?<!\*)\*\*\*(?=\S)(.+?)(?<=\S)\*\*\*(?!\*)"#,
                #"(?<!_)___(?=\S)(.+?)(?<=\S)___(?!_)"#
            ],
            style: .boldItalic,
            in: text,
            protectedRanges: protectedRanges
        )
        let nestedBoldItalicSpans = nestedDelimitedInlineSpans(
            matching: [
                #"(?<!_)__(\*)(?=\S)(.+?)(?<=\S)\1__(?!_)"#,
                #"(?<!\*)\*\*(_)(?=\S)(.+?)(?<=\S)\1\*\*(?!\*)"#,
                #"(?<!_)\_(\*\*)(?=\S)(.+?)(?<=\S)\1_(?!_)"#,
                #"(?<!\*)\*(__)(?=\S)(.+?)(?<=\S)\1\*(?!\*)"#
            ],
            style: .boldItalic,
            in: text,
            protectedRanges: protectedRanges + boldItalicSpans.map(\.fullRange)
        )
        let boldSpans = delimitedInlineSpans(
            matching: [
                #"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#,
                #"(?<!_)__(?=\S)(.+?)(?<=\S)__(?!_)"#
            ],
            style: .bold,
            in: text,
            protectedRanges: protectedRanges + boldItalicSpans.map(\.fullRange) + nestedBoldItalicSpans.map(\.fullRange)
        )
        let italicSpans = delimitedInlineSpans(
            matching: [
                #"(?<!\*)\*(?=\S)(.+?)(?<=\S)\*(?!\*)"#,
                #"(?<!_)_(?=\S)(.+?)(?<=\S)_(?!_)"#
            ],
            style: .italic,
            in: text,
            protectedRanges: protectedRanges
                + boldItalicSpans.map(\.fullRange)
                + nestedBoldItalicSpans.map(\.fullRange)
                + boldSpans.map(\.fullRange)
        )
        let strikethroughSpans = delimitedInlineSpans(
            matching: [#"~~(?=\S)(.+?)(?<=\S)~~"#],
            style: .strikethrough,
            in: text,
            protectedRanges: protectedRanges
        )

        return boldItalicSpans + nestedBoldItalicSpans + boldSpans + italicSpans + strikethroughSpans
    }

    func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
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

    func trimmedLineRange(
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

    func isEscaped(
        location: Int,
        in text: NSString
    ) -> Bool {
        guard location > 0 else {
            return false
        }

        var index = location - 1
        var backslashCount = 0
        while index >= 0, text.character(at: index) == 92 {
            backslashCount += 1
            index -= 1
        }

        return backslashCount.isMultiple(of: 2) == false
    }

    func isEscaped(
        location: Int,
        in text: String
    ) -> Bool {
        isEscaped(location: location, in: text as NSString)
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

    private func delimitedInlineSpans(
        matching patterns: [String],
        style: MarkdownInlineStyleKind,
        in text: String,
        protectedRanges: [NSRange]
    ) -> [MarkdownDelimitedInlineSpan] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return patterns.flatMap { pattern in
            regex(for: pattern).matches(in: text, options: [], range: range).compactMap { match in
                guard match.numberOfRanges == 2 else {
                    return nil
                }

                let fullRange = match.range(at: 0)
                guard
                    protectedRanges.contains(where: { NSIntersectionRange($0, fullRange).length > 0 }) == false,
                    isEscaped(location: fullRange.location, in: nsText) == false
                else {
                    return nil
                }

                let contentRange = match.range(at: 1)
                let leadingMarkerLength = contentRange.location - fullRange.location
                let trailingMarkerLength = NSMaxRange(fullRange) - NSMaxRange(contentRange)
                let markerRanges = [
                    NSRange(location: fullRange.location, length: leadingMarkerLength),
                    NSRange(location: NSMaxRange(contentRange), length: trailingMarkerLength)
                ]

                return MarkdownDelimitedInlineSpan(
                    style: style,
                    fullRange: fullRange,
                    contentRange: contentRange,
                    markerRanges: markerRanges
                )
            }
        }
    }

    private func nestedDelimitedInlineSpans(
        matching patterns: [String],
        style: MarkdownInlineStyleKind,
        in text: String,
        protectedRanges: [NSRange]
    ) -> [MarkdownDelimitedInlineSpan] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return patterns.flatMap { pattern in
            regex(for: pattern).matches(in: text, options: [], range: range).compactMap { match in
                guard match.numberOfRanges == 3 else {
                    return nil
                }

                let fullRange = match.range(at: 0)
                guard
                    protectedRanges.contains(where: { NSIntersectionRange($0, fullRange).length > 0 }) == false,
                    isEscaped(location: fullRange.location, in: nsText) == false
                else {
                    return nil
                }

                let innerMarkerRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let innerMarkerLength = innerMarkerRange.length
                let leadingOuterLength = innerMarkerRange.location - fullRange.location
                let trailingOuterLength = NSMaxRange(fullRange) - NSMaxRange(contentRange) - innerMarkerLength

                let leadingOuterRange = NSRange(location: fullRange.location, length: leadingOuterLength)
                let leadingInnerRange = NSRange(location: innerMarkerRange.location, length: innerMarkerLength)
                let trailingInnerRange = NSRange(location: NSMaxRange(contentRange), length: innerMarkerLength)
                let trailingOuterRange = NSRange(
                    location: NSMaxRange(trailingInnerRange),
                    length: trailingOuterLength
                )

                return MarkdownDelimitedInlineSpan(
                    style: style,
                    fullRange: fullRange,
                    contentRange: contentRange,
                    markerRanges: [
                        leadingOuterRange,
                        leadingInnerRange,
                        trailingInnerRange,
                        trailingOuterRange
                    ]
                )
            }
        }
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
            fatalError("Invalid markdown syntax regex: \(pattern)")
        }
    }
}
