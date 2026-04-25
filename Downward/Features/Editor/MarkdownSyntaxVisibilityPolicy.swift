import Foundation

nonisolated struct MarkdownSyntaxVisibilityPolicy: Equatable, Sendable {
    let syntaxMode: MarkdownSyntaxMode
    let revealedRange: NSRange?

    func shouldHideSyntax(
        in range: NSRange,
        rule: MarkdownSyntaxVisibilityRule
    ) -> Bool {
        switch rule {
        case .alwaysHidden:
            return true
        case .followsMode:
            if syntaxMode != .hiddenOutsideCurrentLine {
                return false
            }

            if let revealedRange, NSIntersectionRange(revealedRange, range).length > 0 {
                return false
            }

            return true
        }
    }
}
