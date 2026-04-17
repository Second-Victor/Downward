import Foundation

enum MarkdownSyntaxMode: String, CaseIterable, Codable, Equatable, Sendable {
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
            "Formatting markers stay visible while bold, italic, and other supported markdown still render."
        case .hiddenOutsideCurrentLine:
            "Formatting markers hide away from the current line so styled text reads more like a finished document."
        }
    }
}
