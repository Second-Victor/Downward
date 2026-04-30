import Foundation

nonisolated struct MarkdownInlineFormatPlan: Equatable {
    let replacement: String
    let selectedRangeInReplacement: NSRange

    static func make(marker: String, selectedText: String) -> MarkdownInlineFormatPlan {
        let markerLength = (marker as NSString).length
        let selectedTextLength = (selectedText as NSString).length

        if selectedText.isEmpty {
            return MarkdownInlineFormatPlan(
                replacement: "\(marker)\(marker)",
                selectedRangeInReplacement: NSRange(location: markerLength, length: 0)
            )
        }

        if selectedText.hasPrefix(marker),
           selectedText.hasSuffix(marker),
           selectedTextLength >= markerLength * 2 {
            let inner = (selectedText as NSString).substring(
                with: NSRange(location: markerLength, length: selectedTextLength - markerLength * 2)
            )
            return MarkdownInlineFormatPlan(
                replacement: inner,
                selectedRangeInReplacement: NSRange(location: 0, length: (inner as NSString).length)
            )
        }

        return MarkdownInlineFormatPlan(
            replacement: "\(marker)\(selectedText)\(marker)",
            selectedRangeInReplacement: NSRange(location: markerLength, length: selectedTextLength)
        )
    }
}

nonisolated struct MarkdownCodeBlockPlan: Equatable {
    private static let fence = "```"

    let replacement: String
    let selectedRangeInReplacement: NSRange

    static func make(selectedText: String) -> MarkdownCodeBlockPlan {
        if let unwrapped = unwrappedCodeBlockContent(from: selectedText) {
            return MarkdownCodeBlockPlan(
                replacement: unwrapped,
                selectedRangeInReplacement: NSRange(location: 0, length: (unwrapped as NSString).length)
            )
        }

        let lineEnding = firstLineEnding(in: selectedText) ?? "\n"

        if selectedText.isEmpty {
            let replacement = "\(fence)\(lineEnding)\(lineEnding)\(fence)\(lineEnding)"
            return MarkdownCodeBlockPlan(
                replacement: replacement,
                selectedRangeInReplacement: NSRange(
                    location: (fence + lineEnding).utf16.count,
                    length: 0
                )
            )
        }

        let closeSeparator = selectedText.hasSuffix(lineEnding) ? "" : lineEnding
        let replacement = "\(fence)\(lineEnding)\(selectedText)\(closeSeparator)\(fence)"
        return MarkdownCodeBlockPlan(
            replacement: replacement,
            selectedRangeInReplacement: NSRange(
                location: (fence + lineEnding).utf16.count,
                length: (selectedText as NSString).length
            )
        )
    }

    private static func unwrappedCodeBlockContent(from selectedText: String) -> String? {
        for lineEnding in ["\r\n", "\n", "\r"] {
            let opening = fence + lineEnding
            let closing = lineEnding + fence
            guard selectedText.hasPrefix(opening),
                  selectedText.hasSuffix(closing),
                  (selectedText as NSString).length >= (opening + closing).utf16.count
            else {
                continue
            }

            let nsText = selectedText as NSString
            return nsText.substring(
                with: NSRange(
                    location: opening.utf16.count,
                    length: nsText.length - opening.utf16.count - closing.utf16.count
                )
            )
        }

        return nil
    }

    private static func firstLineEnding(in text: String) -> String? {
        let nsText = text as NSString
        var index = 0
        while index < nsText.length {
            let character = nsText.character(at: index)
            if character == 0x0D {
                let next = index + 1
                if next < nsText.length, nsText.character(at: next) == 0x0A {
                    return "\r\n"
                }
                return "\r"
            }
            if character == 0x0A {
                return "\n"
            }
            index += 1
        }
        return nil
    }
}

nonisolated struct MarkdownLinePrefixPlan: Equatable {
    let replacement: String
    let selectedRangeInReplacement: NSRange?

    static func make(
        prefix: String,
        selectedText: String,
        selectedRangeInSelectedText: NSRange? = nil
    ) -> MarkdownLinePrefixPlan {
        if let level = MarkdownHeadingPlan.level(forPrefix: prefix) {
            let plan = MarkdownHeadingPlan.make(
                level: level,
                selectedText: selectedText,
                selectedRangeInSelectedText: selectedRangeInSelectedText
            )
            return MarkdownLinePrefixPlan(
                replacement: plan.replacement,
                selectedRangeInReplacement: plan.selectedRangeInReplacement
            )
        }

        if prefix == MarkdownTaskListPlan.uncheckedPrefix {
            let plan = MarkdownTaskListPlan.make(
                selectedText: selectedText,
                selectedRangeInSelectedText: selectedRangeInSelectedText
            )
            return MarkdownLinePrefixPlan(
                replacement: plan.replacement,
                selectedRangeInReplacement: plan.selectedRangeInReplacement
            )
        }

        let parsed = MarkdownLineParser.parse(selectedText)
        let lines = parsed.transformableSegments
        let allPrefixed = lines.allSatisfy { $0.content.isEmpty || $0.content.hasPrefix(prefix) }
        let shouldStrip = allPrefixed && lines.contains(where: { $0.content.hasPrefix(prefix) })

        let result = parsed.replacingTransformableSegments(
            tracking: selectedRangeInSelectedText
        ) { segment, cursorLocal in
            let contentLength = (segment.content as NSString).length
            if shouldStrip, segment.content.hasPrefix(prefix) {
                let prefixLength = (prefix as NSString).length
                return (
                    MarkdownLineSegment(
                        content: String(segment.content.dropFirst(prefix.count)),
                        lineEnding: segment.lineEnding
                    ),
                    cursorLocal.map { max(0, min(contentLength - prefixLength, $0 - prefixLength)) }
                )
            }

            let prefixLength = (prefix as NSString).length
            return (
                MarkdownLineSegment(
                    content: prefix + segment.content,
                    lineEnding: segment.lineEnding
                ),
                cursorLocal.map { prefixLength + $0 }
            )
        }
        return MarkdownLinePrefixPlan(
            replacement: result.replacement,
            selectedRangeInReplacement: result.selectedRangeInReplacement
        )
    }
}

nonisolated struct MarkdownHeadingPlan: Equatable {
    let replacement: String
    let selectedRangeInReplacement: NSRange?

    static func make(
        level: Int,
        selectedText: String,
        selectedRangeInSelectedText: NSRange? = nil
    ) -> MarkdownHeadingPlan {
        let clampedLevel = min(max(level, 1), 6)
        let headingPrefix = String(repeating: "#", count: clampedLevel) + " "

        if selectedText.isEmpty {
            return MarkdownHeadingPlan(
                replacement: headingPrefix,
                selectedRangeInReplacement: selectedRangeInSelectedText?.length == 0
                    ? NSRange(location: (headingPrefix as NSString).length, length: 0)
                    : nil
            )
        }

        let parsed = MarkdownLineParser.parse(selectedText)
        let result = parsed.replacingTransformableSegments(
            tracking: selectedRangeInSelectedText
        ) { segment, cursorLocal in
            let content = segment.content
            guard content.trimmingCharacters(in: .whitespaces).isEmpty == false else {
                return (segment, cursorLocal)
            }

            let indent = content.leadingMarkdownWhitespace
            let indentLength = (indent as NSString).length
            let headingPrefixLength = (headingPrefix as NSString).length
            let bodyStart = content.index(content.startIndex, offsetBy: indent.count)
            let body = String(content[bodyStart...])
            let markerLength = body.leadingMarkdownHeadingMarkerLength ?? 0
            let replacement = MarkdownLineSegment(
                content: indent + headingPrefix + body.removingLeadingMarkdownHeadingMarker,
                lineEnding: segment.lineEnding
            )
            let replacementContentLength = (replacement.content as NSString).length
            let mappedCursor = cursorLocal.map { local in
                guard local >= indentLength else {
                    return local
                }

                let bodyLocal = local - indentLength
                if markerLength > 0 {
                    if bodyLocal <= markerLength {
                        return min(replacementContentLength, indentLength + headingPrefixLength)
                    }
                    return min(
                        replacementContentLength,
                        indentLength + headingPrefixLength + bodyLocal - markerLength
                    )
                }

                return min(replacementContentLength, indentLength + headingPrefixLength + bodyLocal)
            }
            return (replacement, mappedCursor)
        }
        return MarkdownHeadingPlan(
            replacement: result.replacement,
            selectedRangeInReplacement: result.selectedRangeInReplacement
        )
    }

    static func level(forPrefix prefix: String) -> Int? {
        guard prefix.hasSuffix(" ") else {
            return nil
        }
        let marker = prefix.dropLast()
        guard marker.isEmpty == false, marker.count <= 6, marker.allSatisfy({ $0 == "#" }) else {
            return nil
        }
        return marker.count
    }
}

nonisolated struct MarkdownTaskListPlan: Equatable {
    static let uncheckedPrefix = "- [ ] "

    let replacement: String
    let selectedRangeInReplacement: NSRange?

    static func make(
        selectedText: String,
        selectedRangeInSelectedText: NSRange? = nil
    ) -> MarkdownTaskListPlan {
        if selectedText.isEmpty {
            return MarkdownTaskListPlan(
                replacement: uncheckedPrefix,
                selectedRangeInReplacement: selectedRangeInSelectedText?.length == 0
                    ? NSRange(location: (uncheckedPrefix as NSString).length, length: 0)
                    : nil
            )
        }

        let parsed = MarkdownLineParser.parse(selectedText)
        let transformableSegments = parsed.transformableSegments
        let nonEmptySegments = transformableSegments.filter {
            $0.content.trimmingCharacters(in: .whitespaces).isEmpty == false
        }
        let shouldStripTasks = nonEmptySegments.isEmpty == false && nonEmptySegments.allSatisfy {
            MarkdownTaskLine.parse($0.content) != nil
        }

        let result = parsed.replacingTransformableSegments(
            tracking: selectedRangeInSelectedText
        ) { segment, cursorLocal in
            let content = segment.content
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                guard cursorLocal != nil else {
                    return (segment, cursorLocal)
                }

                let prefixLength = (uncheckedPrefix as NSString).length
                let contentLength = (content as NSString).length
                return (
                    MarkdownLineSegment(
                        content: content + uncheckedPrefix,
                        lineEnding: segment.lineEnding
                    ),
                    contentLength + prefixLength
                )
            }

            if let task = MarkdownTaskLine.parse(content) {
                let indentLength = (task.indent as NSString).length
                if shouldStripTasks {
                    let replacement = MarkdownLineSegment(
                        content: task.indent + task.text,
                        lineEnding: segment.lineEnding
                    )
                    let replacementLength = (replacement.content as NSString).length
                    let mappedCursor = cursorLocal.map { local in
                        guard local > task.fullMarkerLength else {
                            return indentLength
                        }
                        return min(replacementLength, indentLength + local - task.fullMarkerLength)
                    }
                    return (replacement, mappedCursor)
                }

                let normalizedMarkerLength = ("- \(task.checkbox) " as NSString).length
                let replacement = MarkdownLineSegment(
                    content: "\(task.indent)- \(task.checkbox) \(task.text)",
                    lineEnding: segment.lineEnding
                )
                let replacementLength = (replacement.content as NSString).length
                let mappedCursor = cursorLocal.map { local in
                    guard local > task.fullMarkerLength else {
                        return indentLength + normalizedMarkerLength
                    }
                    return min(
                        replacementLength,
                        indentLength + normalizedMarkerLength + local - task.fullMarkerLength
                    )
                }
                return (replacement, mappedCursor)
            }

            let prefixLength = (uncheckedPrefix as NSString).length
            return (
                MarkdownLineSegment(
                    content: uncheckedPrefix + content,
                    lineEnding: segment.lineEnding
                ),
                cursorLocal.map { prefixLength + $0 }
            )
        }
        return MarkdownTaskListPlan(
            replacement: result.replacement,
            selectedRangeInReplacement: result.selectedRangeInReplacement
        )
    }
}

nonisolated struct MarkdownLinkInsertionPlan: Equatable {
    let replacement: String
    let selectedRangeInReplacement: NSRange

    static func make(forSelectedText selectedText: String) -> MarkdownLinkInsertionPlan {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let labelPlaceholder = "text"
            let urlPlaceholder = "https://"
            return MarkdownLinkInsertionPlan(
                replacement: "[\(labelPlaceholder)](\(urlPlaceholder))",
                selectedRangeInReplacement: NSRange(location: 1, length: (labelPlaceholder as NSString).length)
            )
        }

        if let destination = MarkdownFormattingURLClassifier.markdownDestination(for: trimmed) {
            let labelPlaceholder = "link"
            return MarkdownLinkInsertionPlan(
                replacement: "[\(labelPlaceholder)](\(destination))",
                selectedRangeInReplacement: NSRange(location: 1, length: (labelPlaceholder as NSString).length)
            )
        }

        let label = MarkdownLabelEscaper.escape(selectedText)
        let urlPlaceholder = "https://"
        return MarkdownLinkInsertionPlan(
            replacement: "[\(label)](\(urlPlaceholder))",
            selectedRangeInReplacement: NSRange(
                location: (label as NSString).length + 3,
                length: (urlPlaceholder as NSString).length
            )
        )
    }
}

nonisolated struct MarkdownImageInsertionPlan: Equatable {
    let replacement: String
    let selectedRangeInReplacement: NSRange

    static func make(forSelectedText selectedText: String) -> MarkdownImageInsertionPlan {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let altPlaceholder = "alt text"
            let urlPlaceholder = "https://"
            return MarkdownImageInsertionPlan(
                replacement: "![\(altPlaceholder)](\(urlPlaceholder))",
                selectedRangeInReplacement: NSRange(location: 2, length: (altPlaceholder as NSString).length)
            )
        }

        if let destination = MarkdownFormattingURLClassifier.markdownDestination(for: trimmed) {
            let altPlaceholder = "alt text"
            return MarkdownImageInsertionPlan(
                replacement: "![\(altPlaceholder)](\(destination))",
                selectedRangeInReplacement: NSRange(location: 2, length: (altPlaceholder as NSString).length)
            )
        }

        let altText = MarkdownLabelEscaper.escape(selectedText)
        let urlPlaceholder = "https://"
        return MarkdownImageInsertionPlan(
            replacement: "![\(altText)](\(urlPlaceholder))",
            selectedRangeInReplacement: NSRange(
                location: (altText as NSString).length + 4,
                length: (urlPlaceholder as NSString).length
            )
        )
    }
}

nonisolated enum MarkdownFormattingURLClassifier {
    private static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms"]

    static func isLikelyMarkdownURL(_ text: String) -> Bool {
        markdownDestination(for: text) != nil
    }

    static func markdownDestination(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased() {
            guard allowedSchemes.contains(scheme) else {
                return nil
            }
            if scheme == "http" || scheme == "https" {
                return components.host?.isEmpty == false ? trimmed : nil
            }
            return trimmed
        }

        if trimmed.lowercased().hasPrefix("www."), trimmed.dropFirst(4).contains(".") {
            return trimmed
        }

        if isBareEmailAddress(trimmed) {
            return "mailto:\(trimmed)"
        }

        return nil
    }

    private static func isBareEmailAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].contains(".") else {
            return false
        }
        return text.contains(":") == false
    }
}

nonisolated enum MarkdownExternalLinkURL {
    static func url(forMarkdownDestination destination: String) -> URL? {
        guard let safeDestination = MarkdownFormattingURLClassifier.markdownDestination(for: destination) else {
            return nil
        }

        if safeDestination.lowercased().hasPrefix("www.") {
            return URL(string: "https://\(safeDestination)")
        }

        return URL(string: safeDestination)
    }
}

nonisolated struct MarkdownLineSegment: Equatable {
    var content: String
    var lineEnding: String
}

private nonisolated struct ParsedMarkdownLines {
    var segments: [MarkdownLineSegment]

    var transformableSegments: [MarkdownLineSegment] {
        if hasTrailingEmptySentinel {
            return Array(segments.dropLast())
        }
        return segments
    }

    func replacingTransformableSegments(
        _ transform: (MarkdownLineSegment) -> MarkdownLineSegment
    ) -> String {
        let transformedCount = transformableSegments.count
        var updatedSegments = segments
        for index in 0..<transformedCount {
            updatedSegments[index] = transform(updatedSegments[index])
        }
        return updatedSegments.map { $0.content + $0.lineEnding }.joined()
    }

    func replacingTransformableSegments(
        tracking selectedRange: NSRange?,
        _ transform: (MarkdownLineSegment, Int?) -> (MarkdownLineSegment, Int?)
    ) -> (replacement: String, selectedRangeInReplacement: NSRange?) {
        let transformedCount = transformableSegments.count
        let shouldTrackCursor = selectedRange?.length == 0
        var replacement = ""
        var originalOffset = 0
        var replacementOffset = 0
        var mappedCursorLocation: Int?

        for index in segments.indices {
            let segment = segments[index]
            let isTransformable = index < transformedCount
            let contentLength = (segment.content as NSString).length
            let lineEndingLength = (segment.lineEnding as NSString).length
            let cursorLocal: Int?
            if
                shouldTrackCursor,
                mappedCursorLocation == nil,
                let cursorLocation = selectedRange?.location,
                cursorLocation >= originalOffset,
                cursorLocation <= originalOffset + contentLength + lineEndingLength
            {
                cursorLocal = min(max(cursorLocation - originalOffset, 0), contentLength)
            } else {
                cursorLocal = nil
            }

            let updatedSegment: MarkdownLineSegment
            let updatedCursorLocal: Int?
            if isTransformable {
                (updatedSegment, updatedCursorLocal) = transform(segment, cursorLocal)
            } else {
                updatedSegment = segment
                updatedCursorLocal = cursorLocal
            }

            if let updatedCursorLocal {
                let updatedContentLength = (updatedSegment.content as NSString).length
                mappedCursorLocation = replacementOffset + min(max(updatedCursorLocal, 0), updatedContentLength)
            }

            replacement += updatedSegment.content + updatedSegment.lineEnding
            originalOffset += contentLength + lineEndingLength
            replacementOffset += (updatedSegment.content as NSString).length
                + (updatedSegment.lineEnding as NSString).length
        }

        if shouldTrackCursor, mappedCursorLocation == nil {
            mappedCursorLocation = replacementOffset
        }

        return (
            replacement,
            mappedCursorLocation.map { NSRange(location: $0, length: 0) }
        )
    }

    private var hasTrailingEmptySentinel: Bool {
        guard let last = segments.last else {
            return false
        }
        return segments.count > 1 && last.content.isEmpty && last.lineEnding.isEmpty
    }
}

private nonisolated enum MarkdownLineParser {
    static func parse(_ text: String) -> ParsedMarkdownLines {
        guard text.isEmpty == false else {
            return ParsedMarkdownLines(segments: [MarkdownLineSegment(content: "", lineEnding: "")])
        }

        let nsText = text as NSString
        var segments: [MarkdownLineSegment] = []
        var lineStart = 0
        var index = 0

        while index < nsText.length {
            let character = nsText.character(at: index)
            if character == 0x0D {
                let next = index + 1
                if next < nsText.length, nsText.character(at: next) == 0x0A {
                    segments.append(
                        MarkdownLineSegment(
                            content: nsText.substring(with: NSRange(location: lineStart, length: index - lineStart)),
                            lineEnding: "\r\n"
                        )
                    )
                    index += 2
                    lineStart = index
                    continue
                }

                segments.append(
                    MarkdownLineSegment(
                        content: nsText.substring(with: NSRange(location: lineStart, length: index - lineStart)),
                        lineEnding: "\r"
                    )
                )
                index += 1
                lineStart = index
                continue
            }

            if character == 0x0A {
                segments.append(
                    MarkdownLineSegment(
                        content: nsText.substring(with: NSRange(location: lineStart, length: index - lineStart)),
                        lineEnding: "\n"
                    )
                )
                index += 1
                lineStart = index
                continue
            }

            index += 1
        }

        segments.append(
            MarkdownLineSegment(
                content: nsText.substring(with: NSRange(location: lineStart, length: nsText.length - lineStart)),
                lineEnding: ""
            )
        )
        return ParsedMarkdownLines(segments: segments)
    }
}

private nonisolated enum MarkdownLabelEscaper {
    static func escape(_ text: String) -> String {
        text.replacingLineBreaksWithSpaces()
            .replacingOccurrences(of: "[", with: #"\["#)
            .replacingOccurrences(of: "]", with: #"\]"#)
    }
}

private nonisolated struct MarkdownTaskLine {
    let indent: String
    let checkbox: String
    let text: String
    let fullMarkerLength: Int

    static func parse(_ line: String) -> MarkdownTaskLine? {
        let indent = line.leadingMarkdownWhitespace
        let indentLength = (indent as NSString).length
        let bodyStart = line.index(line.startIndex, offsetBy: indent.count)
        let body = String(line[bodyStart...])

        guard let markerEnd = taskListMarkerEnd(in: body) else {
            return nil
        }

        let markerRemainder = String(body[markerEnd...])
        guard markerRemainder.hasPrefix("[ ] ")
            || markerRemainder.hasPrefix("[x] ")
            || markerRemainder.hasPrefix("[X] ")
            || markerRemainder.hasPrefix("[/] ")
        else {
            return nil
        }

        let checkbox = String(markerRemainder.prefix(3)).lowercased()
        let textStart = markerRemainder.index(markerRemainder.startIndex, offsetBy: 4)
        return MarkdownTaskLine(
            indent: indent,
            checkbox: checkbox,
            text: String(markerRemainder[textStart...]),
            fullMarkerLength: indentLength
                + (String(body[..<markerEnd]) as NSString).length
                + ("[ ] " as NSString).length
        )
    }

    private static func taskListMarkerEnd(in body: String) -> String.Index? {
        if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
            return body.index(body.startIndex, offsetBy: 2)
        }

        var index = body.startIndex
        var digitCount = 0
        while index < body.endIndex, body[index].isNumber {
            digitCount += 1
            index = body.index(after: index)
        }

        guard digitCount > 0,
              index < body.endIndex,
              body[index] == "."
        else {
            return nil
        }

        let afterPeriod = body.index(after: index)
        guard afterPeriod < body.endIndex, body[afterPeriod] == " " else {
            return nil
        }
        return body.index(after: afterPeriod)
    }
}

private extension String {
    nonisolated var leadingMarkdownWhitespace: String {
        String(prefix { $0 == " " || $0 == "\t" })
    }

    nonisolated var removingLeadingMarkdownHeadingMarker: String {
        guard let markerEnd = leadingMarkdownHeadingMarkerEnd else {
            return self
        }
        return String(self[markerEnd...])
    }

    nonisolated var leadingMarkdownHeadingMarkerLength: Int? {
        guard let markerEnd = leadingMarkdownHeadingMarkerEnd else {
            return nil
        }
        return (String(self[..<markerEnd]) as NSString).length
    }

    nonisolated private var leadingMarkdownHeadingMarkerEnd: String.Index? {
        var index = startIndex
        var markerCount = 0
        while index < endIndex, self[index] == "#", markerCount < 6 {
            markerCount += 1
            index = self.index(after: index)
        }

        guard markerCount > 0 else {
            return nil
        }

        if index == endIndex {
            return index
        }

        guard self[index] == " " || self[index] == "\t" else {
            return nil
        }

        while index < endIndex, self[index] == " " || self[index] == "\t" {
            index = self.index(after: index)
        }
        return index
    }

    nonisolated func replacingLineBreaksWithSpaces() -> String {
        let nsText = self as NSString
        var result = ""
        var segmentStart = 0
        var index = 0
        var previousWasLineBreak = false

        while index < nsText.length {
            let character = nsText.character(at: index)
            let lineBreakLength: Int?
            if character == 0x0D {
                let next = index + 1
                lineBreakLength = next < nsText.length && nsText.character(at: next) == 0x0A ? 2 : 1
            } else if character == 0x0A {
                lineBreakLength = 1
            } else {
                lineBreakLength = nil
            }

            if let lineBreakLength {
                result += nsText.substring(with: NSRange(location: segmentStart, length: index - segmentStart))
                if previousWasLineBreak == false {
                    result.append(" ")
                    previousWasLineBreak = true
                }
                index += lineBreakLength
                segmentStart = index
            } else {
                previousWasLineBreak = false
                index += 1
            }
        }

        result += nsText.substring(with: NSRange(location: segmentStart, length: nsText.length - segmentStart))
        return result
    }
}
