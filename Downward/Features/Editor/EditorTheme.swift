import UIKit

struct EditorTheme: Identifiable, Equatable {
    let id: String
    let label: String
    let background: UIColor
    let text: UIColor
    let tint: UIColor
    let boldItalicMarker: UIColor
    let inlineCode: UIColor
    let codeBackground: UIColor
    let horizontalRule: UIColor
    let checkboxUnchecked: UIColor
    let checkboxChecked: UIColor

    static let adaptive = EditorTheme(
        id: "adaptive",
        label: "Adaptive",
        background: .systemBackground,
        text: .label,
        tint: .systemBlue,
        boldItalicMarker: .secondaryLabel,
        inlineCode: .label,
        codeBackground: .secondarySystemFill,
        horizontalRule: .tertiaryLabel,
        checkboxUnchecked: .systemRed,
        checkboxChecked: .systemGreen
    )

    static let greyAdaptive = EditorTheme(
        id: "grey-adaptive",
        label: "Grey Adaptive",
        background: .secondarySystemBackground,
        text: .label,
        tint: .systemGray,
        boldItalicMarker: .secondaryLabel,
        inlineCode: .label,
        codeBackground: .tertiarySystemFill,
        horizontalRule: .tertiaryLabel,
        checkboxUnchecked: .systemRed,
        checkboxChecked: .systemGreen
    )

    static let monokai = EditorTheme(
        id: "monokai",
        label: "Monokai",
        background: UIColor(red: 0.12, green: 0.13, blue: 0.11, alpha: 1),
        text: UIColor(red: 0.82, green: 0.82, blue: 0.78, alpha: 1),
        tint: UIColor(red: 0.40, green: 0.63, blue: 0.85, alpha: 1),
        boldItalicMarker: UIColor(red: 0.49, green: 0.49, blue: 0.55, alpha: 1),
        inlineCode: UIColor(red: 0.78, green: 0.54, blue: 0.43, alpha: 1),
        codeBackground: UIColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1),
        horizontalRule: UIColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 1),
        checkboxUnchecked: UIColor(red: 0.95, green: 0.28, blue: 0.28, alpha: 1),
        checkboxChecked: UIColor(red: 0.42, green: 0.60, blue: 0.33, alpha: 1)
    )

    static let solarized = EditorTheme(
        id: "solarized",
        label: "Solarized",
        background: UIColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1),
        text: UIColor(red: 0.03, green: 0.21, blue: 0.26, alpha: 1),
        tint: UIColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1),
        boldItalicMarker: UIColor(red: 0.35, green: 0.43, blue: 0.46, alpha: 1),
        inlineCode: UIColor(red: 0.80, green: 0.29, blue: 0.09, alpha: 1),
        codeBackground: UIColor(red: 0.93, green: 0.90, blue: 0.82, alpha: 1),
        horizontalRule: UIColor(red: 0.58, green: 0.63, blue: 0.63, alpha: 1),
        checkboxUnchecked: UIColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1),
        checkboxChecked: UIColor(red: 0.52, green: 0.60, blue: 0.00, alpha: 1)
    )

    static let builtIn = [adaptive, greyAdaptive, monokai, solarized]

    static func loadingCustomTheme(id: String) -> EditorTheme {
        EditorTheme(
            id: id,
            label: "Loading Theme",
            background: .systemBackground,
            text: .label,
            tint: .systemBlue,
            boldItalicMarker: .secondaryLabel,
            inlineCode: .label,
            codeBackground: .secondarySystemFill,
            horizontalRule: .tertiaryLabel,
            checkboxUnchecked: .systemRed,
            checkboxChecked: .systemGreen
        )
    }

    static func failedCustomTheme(id: String) -> EditorTheme {
        EditorTheme(
            id: id,
            label: "Missing Theme",
            background: .systemBackground,
            text: .label,
            tint: .systemOrange,
            boldItalicMarker: .secondaryLabel,
            inlineCode: .label,
            codeBackground: .secondarySystemFill,
            horizontalRule: .tertiaryLabel,
            checkboxUnchecked: .systemRed,
            checkboxChecked: .systemGreen
        )
    }

    init(
        id: String,
        label: String,
        background: UIColor,
        text: UIColor,
        tint: UIColor,
        boldItalicMarker: UIColor,
        inlineCode: UIColor,
        codeBackground: UIColor,
        horizontalRule: UIColor,
        checkboxUnchecked: UIColor,
        checkboxChecked: UIColor
    ) {
        self.id = id
        self.label = label
        self.background = background
        self.text = text
        self.tint = tint
        self.boldItalicMarker = boldItalicMarker
        self.inlineCode = inlineCode
        self.codeBackground = codeBackground
        self.horizontalRule = horizontalRule
        self.checkboxUnchecked = checkboxUnchecked
        self.checkboxChecked = checkboxChecked
    }

    init(from customTheme: CustomTheme) {
        self.init(
            id: customTheme.id.uuidString,
            label: customTheme.name,
            background: customTheme.background.uiColor,
            text: customTheme.text.uiColor,
            tint: customTheme.tint.uiColor,
            boldItalicMarker: customTheme.boldItalicMarker.uiColor,
            inlineCode: customTheme.inlineCode.uiColor,
            codeBackground: customTheme.codeBackground.uiColor,
            horizontalRule: customTheme.horizontalRule.uiColor,
            checkboxUnchecked: customTheme.checkboxUnchecked.uiColor,
            checkboxChecked: customTheme.checkboxChecked.uiColor
        )
    }

    var resolvedEditorTheme: ResolvedEditorTheme {
        ResolvedEditorTheme(
            editorBackground: background,
            keyboardAccessoryUnderlayBackground: background,
            accent: tint,
            primaryText: text,
            secondaryText: text.withAlphaComponent(0.72),
            tertiaryText: text.withAlphaComponent(0.45),
            headingText: text,
            emphasisText: text,
            strikethroughText: text.withAlphaComponent(0.62),
            syntaxMarkerText: boldItalicMarker,
            subtleSyntaxMarkerText: horizontalRule,
            linkText: tint,
            imageAltText: text.withAlphaComponent(0.72),
            inlineCodeText: inlineCode,
            inlineCodeBackground: codeBackground,
            codeBlockText: text,
            codeBlockBackground: codeBackground,
            blockquoteText: text,
            blockquoteBackground: codeBackground,
            blockquoteBar: horizontalRule,
            horizontalRuleText: horizontalRule
        )
    }
}
