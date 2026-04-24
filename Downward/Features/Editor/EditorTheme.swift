import UIKit

struct EditorTheme: Identifiable, Equatable {
    let id: String
    let label: String
    let background: UIColor
    let text: UIColor
    let tint: UIColor
    let boldItalicMarker: UIColor
    let strikethrough: UIColor
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
        strikethrough: .label.withAlphaComponent(0.62),
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
        strikethrough: .label.withAlphaComponent(0.62),
        inlineCode: .label,
        codeBackground: .tertiarySystemFill,
        horizontalRule: .tertiaryLabel,
        checkboxUnchecked: .systemRed,
        checkboxChecked: .systemGreen
    )

    static let builtIn = [adaptive, greyAdaptive]

    static func loadingCustomTheme(id: String) -> EditorTheme {
        EditorTheme(
            id: id,
            label: "Loading Theme",
            background: .systemBackground,
            text: .label,
            tint: .systemBlue,
            boldItalicMarker: .secondaryLabel,
            strikethrough: .label.withAlphaComponent(0.62),
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
            strikethrough: .label.withAlphaComponent(0.62),
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
        strikethrough: UIColor,
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
        self.strikethrough = strikethrough
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
            strikethrough: customTheme.strikethrough.uiColor,
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
            strikethroughText: strikethrough,
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
