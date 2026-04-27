import Foundation

nonisolated struct TaskListContinuationPlan: Equatable {
    let replacementRange: NSRange
    let replacement: String
    let selectionAfter: NSRange

    // Compile-time pattern for task list lines. It intentionally accepts only Markdown task
    // prefixes so ordinary list continuation remains UIKit's normal text-editing behavior.
    private static let taskLineRegex = try? NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]|\d+\.)([ \t]+)(\[[ xX/]\])([ \t]?)(.*)$"#
    )

    static func make(
        in text: NSString,
        editedRange: NSRange,
        replacementText: String
    ) -> TaskListContinuationPlan? {
        guard
            replacementText == "\n",
            editedRange.length == 0,
            editedRange.location <= text.length
        else {
            return nil
        }

        let lineRange = text.lineRange(for: NSRange(location: editedRange.location, length: 0))
        guard editedRange.location == lineContentEnd(in: text, for: lineRange) else {
            return nil
        }

        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let nsLine = line as NSString
        guard
            let taskLineRegex,
            let match = taskLineRegex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            ),
            match.numberOfRanges == 7
        else {
            return nil
        }

        let indent = nsLine.substring(with: match.range(at: 1))
        let marker = nsLine.substring(with: match.range(at: 2))
        let content = nsLine.substring(with: match.range(at: 6))

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            let replacement = indent
            let replacementRange = lineContentRange(in: text, for: lineRange)
            return TaskListContinuationPlan(
                replacementRange: replacementRange,
                replacement: replacement,
                selectionAfter: NSRange(
                    location: replacementRange.location + (replacement as NSString).length,
                    length: 0
                )
            )
        }

        let nextMarker: String
        if marker.hasSuffix("."),
           let number = Int(marker.dropLast()) {
            nextMarker = "\(number + 1)."
        } else {
            nextMarker = marker
        }

        let replacement = "\n\(indent)\(nextMarker) [ ] "
        return TaskListContinuationPlan(
            replacementRange: editedRange,
            replacement: replacement,
            selectionAfter: NSRange(
                location: editedRange.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    private static func lineContentEnd(in text: NSString, for lineRange: NSRange) -> Int {
        var end = min(NSMaxRange(lineRange), text.length)
        while end > lineRange.location {
            let scalar = text.character(at: end - 1)
            guard scalar == 0x0A || scalar == 0x0D else {
                break
            }
            end -= 1
        }
        return end
    }

    private static func lineContentRange(in text: NSString, for lineRange: NSRange) -> NSRange {
        let end = lineContentEnd(in: text, for: lineRange)
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }
}
