import Foundation

struct EditorAppearancePreferences: Codable, Equatable, Sendable {
    var fontChoice: EditorFontChoice
    var fontSize: Double
    var markdownSyntaxMode: MarkdownSyntaxMode
    var colorFormattedText: Bool
    var selectedThemeID: String
    var matchSystemChromeToTheme: Bool

    init(
        fontChoice: EditorFontChoice,
        fontSize: Double,
        markdownSyntaxMode: MarkdownSyntaxMode = .visible,
        colorFormattedText: Bool = true,
        selectedThemeID: String = EditorTheme.adaptive.id,
        matchSystemChromeToTheme: Bool = true
    ) {
        self.fontChoice = fontChoice
        self.fontSize = fontSize
        self.markdownSyntaxMode = markdownSyntaxMode
        self.colorFormattedText = colorFormattedText
        self.selectedThemeID = selectedThemeID
        self.matchSystemChromeToTheme = matchSystemChromeToTheme
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
        case colorFormattedText
        case selectedThemeID
        case matchSystemChromeToTheme
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontChoice = try container.decode(EditorFontChoice.self, forKey: .fontChoice)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        markdownSyntaxMode = try container.decodeIfPresent(
            MarkdownSyntaxMode.self,
            forKey: .markdownSyntaxMode
        ) ?? .visible
        colorFormattedText = try container.decodeIfPresent(
            Bool.self,
            forKey: .colorFormattedText
        ) ?? true
        selectedThemeID = try container.decodeIfPresent(
            String.self,
            forKey: .selectedThemeID
        ) ?? EditorTheme.adaptive.id
        matchSystemChromeToTheme = try container.decodeIfPresent(
            Bool.self,
            forKey: .matchSystemChromeToTheme
        ) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontChoice, forKey: .fontChoice)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(markdownSyntaxMode, forKey: .markdownSyntaxMode)
        try container.encode(colorFormattedText, forKey: .colorFormattedText)
        try container.encode(selectedThemeID, forKey: .selectedThemeID)
        try container.encode(matchSystemChromeToTheme, forKey: .matchSystemChromeToTheme)
    }
}
