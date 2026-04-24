import XCTest
@testable import Downward

final class SettingsScreenModelTests: XCTestCase {
    @MainActor
    func testHomeSummaryUsesCurrentFontFamily() {
        let store = EditorAppearanceStore(
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .systemMonospaced,
                fontSize: 15
            )
        )

        let summary = SettingsHomeSummary(
            workspaceName: "MarkDown",
            editorAppearanceStore: store
        )

        XCTAssertEqual(summary.fontName, "SF Mono")
    }

    @MainActor
    func testHomeSummaryUsesCurrentThemeName() {
        let summary = SettingsHomeSummary(
            workspaceName: "MarkDown",
            editorAppearanceStore: EditorAppearanceStore(),
            selectedTheme: .greyAdaptive
        )

        XCTAssertEqual(summary.themeName, "Grey Adaptive")
    }

    @MainActor
    func testHomeSummaryUsesCurrentWorkspaceName() {
        let summary = SettingsHomeSummary(
            workspaceName: "Writing",
            editorAppearanceStore: EditorAppearanceStore()
        )

        XCTAssertEqual(summary.workspaceName, "Writing")
    }

    @MainActor
    func testHomeSummaryUsesNoneWhenNoWorkspaceIsLoaded() {
        let summary = SettingsHomeSummary(
            workspaceName: nil,
            editorAppearanceStore: EditorAppearanceStore()
        )

        XCTAssertEqual(summary.workspaceName, "None")
    }

    @MainActor
    func testHomeSummaryUsesCurrentAppearanceName() {
        let summary = SettingsHomeSummary(
            workspaceName: "Writing",
            editorAppearanceStore: EditorAppearanceStore(),
            appearanceName: AppColorScheme.dark.label
        )

        XCTAssertEqual(summary.appearanceName, "Dark")
    }

    @MainActor
    func testEditorFontSelectionUpdatesStore() {
        let store = EditorAppearanceStore(initialPreferences: .default)

        store.setFontChoice(.systemMonospaced)

        XCTAssertEqual(store.selectedFontChoice, .systemMonospaced)
        XCTAssertEqual(
            SettingsHomeSummary(
                workspaceName: "MarkDown",
                editorAppearanceStore: store
            ).fontName,
            "SF Mono"
        )
    }

    @MainActor
    func testMarkdownDisplaySettingUpdatesStore() {
        let store = EditorAppearanceStore(initialPreferences: .default)

        store.setMarkdownSyntaxMode(.hiddenOutsideCurrentLine)
        store.setColorFormattedText(false)

        XCTAssertEqual(store.markdownSyntaxMode, .hiddenOutsideCurrentLine)
        XCTAssertEqual(store.colorFormattedText, false)
    }

    func testPlaceholderSettingsAreNotMarkedImplemented() {
        let placeholders: [SettingsPlaceholderFeature] = [
            .lineNumbers,
            .largerHeadingText,
            .tapToToggleTasks,
            .tipsPurchases,
            .rateTheApp,
            .legalLinks
        ]

        XCTAssertTrue(placeholders.allSatisfy { $0.isImplemented == false })
    }
}
