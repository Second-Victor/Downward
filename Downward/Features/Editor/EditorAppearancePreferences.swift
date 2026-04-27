import Foundation

struct EditorAppearancePreferences: Codable, Equatable, Sendable {
    static let defaultLineNumberOpacity = 0.85

    var fontChoice: EditorFontChoice
    var fontSize: Double
    var markdownSyntaxMode: MarkdownSyntaxMode
    var showLineNumbers: Bool
    var lineNumberOpacity: Double
    var largerHeadingText: Bool
    var colorFormattedText: Bool
    var tapToToggleTasks: Bool
    var selectedThemeID: String
    var matchSystemChromeToTheme: Bool

    init(
        fontChoice: EditorFontChoice,
        fontSize: Double,
        markdownSyntaxMode: MarkdownSyntaxMode = .visible,
        showLineNumbers: Bool = false,
        lineNumberOpacity: Double = Self.defaultLineNumberOpacity,
        largerHeadingText: Bool = false,
        colorFormattedText: Bool = true,
        tapToToggleTasks: Bool = true,
        selectedThemeID: String = EditorTheme.adaptive.id,
        matchSystemChromeToTheme: Bool = true
    ) {
        self.fontChoice = fontChoice
        self.fontSize = fontSize
        self.markdownSyntaxMode = markdownSyntaxMode
        self.showLineNumbers = showLineNumbers
        self.lineNumberOpacity = lineNumberOpacity
        self.largerHeadingText = largerHeadingText
        self.colorFormattedText = colorFormattedText
        self.tapToToggleTasks = tapToToggleTasks
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
        case showLineNumbers
        case lineNumberOpacity
        case largerHeadingText
        case colorFormattedText
        case tapToToggleTasks
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
        showLineNumbers = try container.decodeIfPresent(
            Bool.self,
            forKey: .showLineNumbers
        ) ?? false
        lineNumberOpacity = try container.decodeIfPresent(
            Double.self,
            forKey: .lineNumberOpacity
        ) ?? Self.defaultLineNumberOpacity
        largerHeadingText = try container.decodeIfPresent(
            Bool.self,
            forKey: .largerHeadingText
        ) ?? false
        colorFormattedText = try container.decodeIfPresent(
            Bool.self,
            forKey: .colorFormattedText
        ) ?? true
        tapToToggleTasks = try container.decodeIfPresent(
            Bool.self,
            forKey: .tapToToggleTasks
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
        try container.encode(showLineNumbers, forKey: .showLineNumbers)
        try container.encode(lineNumberOpacity, forKey: .lineNumberOpacity)
        try container.encode(largerHeadingText, forKey: .largerHeadingText)
        try container.encode(colorFormattedText, forKey: .colorFormattedText)
        try container.encode(tapToToggleTasks, forKey: .tapToToggleTasks)
        try container.encode(selectedThemeID, forKey: .selectedThemeID)
        try container.encode(matchSystemChromeToTheme, forKey: .matchSystemChromeToTheme)
    }
}
