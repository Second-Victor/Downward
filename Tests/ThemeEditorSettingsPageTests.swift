import XCTest
@testable import Downward

final class ThemeEditorSettingsPageTests: XCTestCase {
    @MainActor
    func testDraftExportSerializesCurrentDraftTheme() throws {
        let themeID = UUID()
        let savedTheme = Self.makeTheme(id: themeID, name: "Saved Theme", text: "#D4D4D4")
        let draftTheme = Self.makeTheme(id: themeID, name: "Unsaved Draft", text: "#FFFFFF")

        let document = ThemeEditorDraftExport.document(for: draftTheme)
        let decoded = try ThemeExchangeDocument(data: document.exportedData())

        XCTAssertEqual(decoded.themes, [draftTheme])
        XCTAssertNotEqual(decoded.themes, [savedTheme])
    }

    @MainActor
    func testDraftExportUsesDraftLabel() {
        XCTAssertEqual(ThemeEditorDraftExport.buttonTitle, "Export Draft")
    }

    @MainActor
    func testDraftExportRequiresThemeUnlock() {
        XCTAssertFalse(ThemeEntitlementGate.canExportCustomThemes(hasUnlockedThemes: false))
        XCTAssertTrue(ThemeEntitlementGate.canExportCustomThemes(hasUnlockedThemes: true))
    }

    @MainActor
    func testDraftExportedJSONCanBeImportedAgain() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "draft-export-import-\(UUID().uuidString).json")
        let theme = Self.makeTheme(id: UUID(), name: "Portable Draft", text: "#FEFEFE")
        let document = ThemeEditorDraftExport.document(for: theme)
        let decoded = try ThemeExchangeDocument(data: document.exportedData())
        let store = ThemeStore(
            fileURL: fileURL,
            entitlements: ThemeEntitlementStore(hasUnlockedThemes: true),
            bundledPremiumThemes: []
        )
        await store.waitForInitialLoad()

        let didImport = await store.importThemes(decoded.themes)

        XCTAssertTrue(didImport)
        XCTAssertEqual(store.themes, [theme])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testDraftExportFilenameUsesSanitizedThemeName() {
        XCTAssertEqual(
            ThemeEditorDraftExport.filename(for: "  My / Draft: Theme  "),
            "My---Draft--Theme.json"
        )
        XCTAssertEqual(ThemeEditorDraftExport.filename(for: "   "), "Theme.json")
    }

    @MainActor
    func testDraftExportFilenameDoesNotKeepPathHostileCharacters() {
        let filename = ThemeEditorDraftExport.filename(for: " ../Themes\\Draft:Bad*Name?\n ")
        let basename = String(filename.dropLast(".json".count))
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)

        XCTAssertTrue(filename.hasSuffix(".json"))
        XCTAssertNil(basename.rangeOfCharacter(from: illegalCharacters))
    }

    @MainActor
    func testContrastWarningUsesPlainLanguage() {
        let combinedCopy = "\(ThemeContrastWarning.title) \(ThemeContrastWarning.message)"

        XCTAssertEqual(ThemeContrastWarning.minimumReadableRatio, 4.5)
        XCTAssertFalse(combinedCopy.localizedCaseInsensitiveContains("WCAG"))
        XCTAssertFalse(combinedCopy.localizedCaseInsensitiveContains("AA"))
        XCTAssertFalse(combinedCopy.contains(":1"))
        XCTAssertTrue(combinedCopy.localizedCaseInsensitiveContains("hard to read"))
    }

    @MainActor
    func testThemeAccentColorPropertyNamesHeadingAndAccentUsage() {
        XCTAssertEqual(ThemeColorProperty.tint.title, "Heading / Accents")
    }

    @MainActor
    func testThemePreviewUsesFixedFontSizeIndependentOfEditorSettings() {
        let editorAppearanceStore = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .georgia,
                fontSize: 28
            )
        )

        XCTAssertEqual(ThemeEditorPreviewLayout.previewFont.pointSize, ThemeEditorPreviewLayout.previewFontSize)
        XCTAssertNotEqual(editorAppearanceStore.editorUIFont.pointSize, ThemeEditorPreviewLayout.previewFont.pointSize)
    }

    @MainActor
    func testThemePreviewContentMarginLeavesRoomForFixedOverlay() {
        XCTAssertEqual(
            ThemeEditorPreviewLayout.listTopContentMargin,
            ThemeEditorPreviewLayout.previewHeight + ThemeEditorPreviewLayout.topPadding + ThemeEditorPreviewLayout.bottomPadding
        )
    }

    @MainActor
    func testThemePreviewUsesSofterRoundedCorners() {
        XCTAssertEqual(ThemeEditorPreviewLayout.cornerRadius, 16)
    }

    @MainActor
    func testPaletteColorPickerUsesCompactFixedGridOnlyWhenItFits() {
        XCTAssertEqual(PaletteColorPickerLayout.columnCount, 6)
        XCTAssertEqual(PaletteColorPickerLayout.fixedSwatchSize, 56)
        XCTAssertEqual(
            PaletteColorPickerLayout.fixedGridWidth,
            CGFloat(PaletteColorPickerLayout.columnCount) * PaletteColorPickerLayout.fixedSwatchSize
                + CGFloat(PaletteColorPickerLayout.columnCount - 1) * PaletteColorPickerLayout.swatchSpacing
        )
        XCTAssertGreaterThan(PaletteColorPickerLayout.fixedGridWidth, 390)
        XCTAssertLessThan(PaletteColorPickerLayout.fixedGridWidth, 430)
    }

    private static func makeTheme(id: UUID, name: String, text: String) -> CustomTheme {
        CustomTheme(
            id: id,
            name: name,
            background: HexColor(hex: "#1E1E1E"),
            text: HexColor(hex: text),
            tint: HexColor(hex: "#569CD6"),
            boldItalicMarker: HexColor(hex: "#72727F"),
            strikethrough: HexColor(hex: "#808080"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
    }
}
