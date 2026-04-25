import Foundation

/// Markdown syntax visibility is explicit per token.
/// The shipping editor currently lets supported markdown syntax follow
/// `MarkdownSyntaxMode`, including code span delimiters and fenced code fences.
nonisolated enum MarkdownSyntaxMode: String, CaseIterable, Codable, Equatable, Sendable {
    case visible
    case hiddenOutsideCurrentLine

    var displayName: String {
        switch self {
        case .visible:
            "Show Markdown Syntax"
        case .hiddenOutsideCurrentLine:
            "Hide Syntax Outside Current Line"
        }
    }

    var previewDescription: String {
        switch self {
        case .visible:
            "Markdown markers stay visible while rendered styling still applies."
        case .hiddenOutsideCurrentLine:
            "Markdown markers hide away from the current line so styled text reads more like a finished document."
        }
    }
}

/// Explicit renderer policy for how each syntax token responds to `MarkdownSyntaxMode`.
nonisolated enum MarkdownSyntaxVisibilityRule: Int, Equatable, Sendable {
    case followsMode
    case alwaysHidden
}
