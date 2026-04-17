import Foundation

struct EditorAppearancePreferences: Codable, Equatable, Sendable {
    var fontChoice: EditorFontChoice
    var fontSize: Double
    var markdownSyntaxMode: MarkdownSyntaxMode

    init(
        fontChoice: EditorFontChoice,
        fontSize: Double,
        markdownSyntaxMode: MarkdownSyntaxMode = .visible
    ) {
        self.fontChoice = fontChoice
        self.fontSize = fontSize
        self.markdownSyntaxMode = markdownSyntaxMode
    }

    static let `default` = EditorAppearancePreferences(
        fontChoice: .default,
        fontSize: 16,
        markdownSyntaxMode: .visible
    )

    private enum CodingKeys: String, CodingKey {
        case fontChoice
        case fontSize
        case markdownSyntaxMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontChoice = try container.decode(EditorFontChoice.self, forKey: .fontChoice)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        markdownSyntaxMode = try container.decodeIfPresent(
            MarkdownSyntaxMode.self,
            forKey: .markdownSyntaxMode
        ) ?? .visible
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontChoice, forKey: .fontChoice)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(markdownSyntaxMode, forKey: .markdownSyntaxMode)
    }
}
