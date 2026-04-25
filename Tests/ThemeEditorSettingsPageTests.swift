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
    func testDraftExportFilenameUsesSanitizedThemeName() {
        XCTAssertEqual(
            ThemeEditorDraftExport.filename(for: "  My / Draft: Theme  "),
            "My---Draft--Theme.json"
        )
        XCTAssertEqual(ThemeEditorDraftExport.filename(for: "   "), "Theme.json")
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
