import XCTest
@testable import Downward

final class EditorAppearanceStoreTests: XCTestCase {
    @MainActor
    func testEditorAppearanceStorePersistsPreferences() throws {
        let suiteName = "EditorAppearanceStoreTests.\(UUID().uuidString)"
        let userDefaults = try makeIsolatedUserDefaults(suiteName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let resolver = EditorFontResolver(
            isRuntimeFontAvailable: { fontName in
                fontName == "Menlo-Regular"
            }
        )

        let store = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )
        store.setFontChoice(.menlo)
        store.setFontSize(19)
        store.setMarkdownSyntaxMode(.hiddenOutsideCurrentLine)

        let reloadedStore = EditorAppearanceStore(
            userDefaults: userDefaults,
            preferencesKey: "test.editor.appearance",
            resolver: resolver
        )

        XCTAssertEqual(
            reloadedStore.effectivePreferences,
            EditorAppearancePreferences(
                fontChoice: .menlo,
                fontSize: 19,
                markdownSyntaxMode: .hiddenOutsideCurrentLine
            )
        )
    }

    @MainActor
    func testEditorFontResolverFiltersUnavailableNamedFonts() {
        let resolver = EditorFontResolver(
            isRuntimeFontAvailable: { fontName in
                fontName == "Courier"
            }
        )

        XCTAssertEqual(
            resolver.availableChoices,
            [.default, .systemMonospaced, .courier]
        )
    }

    @MainActor
    func testEditorFontResolverFallsBackToDefaultWhenSavedFontIsUnavailable() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { _ in false })

        XCTAssertEqual(resolver.normalizedChoice(.menlo), .default)
        XCTAssertEqual(resolver.normalizedChoice(.courierNew), .default)
    }

    @MainActor
    func testEditorAppearanceStoreClampsFontSizeAndFallsBackForUnavailableChoice() {
        let resolver = EditorFontResolver(isRuntimeFontAvailable: { _ in false })
        let store = EditorAppearanceStore(
            resolver: resolver,
            initialPreferences: EditorAppearancePreferences(
                fontChoice: .courierNew,
                fontSize: 30
            )
        )

        XCTAssertEqual(
            store.effectivePreferences,
            EditorAppearancePreferences(
                fontChoice: .default,
                fontSize: 24,
                markdownSyntaxMode: .visible
            )
        )

        store.setFontSize(10)

        XCTAssertEqual(store.fontSize, 12)
        XCTAssertEqual(store.selectedFontChoice, .default)
    }

    @MainActor
    private func makeIsolatedUserDefaults(suiteName: String) throws -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated UserDefaults suite.")
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
