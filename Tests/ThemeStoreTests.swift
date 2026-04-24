import XCTest
@testable import Downward

final class ThemeStoreTests: XCTestCase {
    @MainActor
    func testThemeStoreAddsAndPersistsCustomTheme() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = ThemeStore(fileURL: fileURL)
        let theme = Self.makeTheme(name: "Night Writing")

        let didAdd = await store.add(theme)
        XCTAssertTrue(didAdd)

        let reloadedStore = ThemeStore(fileURL: fileURL)
        await reloadedStore.waitForInitialLoad()

        XCTAssertEqual(reloadedStore.themes, [theme])
        XCTAssertEqual(reloadedStore.resolve(theme.id.uuidString).label, "Night Writing")
    }

    @MainActor
    func testThemeStoreRejectsDuplicateCustomThemeNames() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = ThemeStore(fileURL: fileURL)
        let firstTheme = Self.makeTheme(id: UUID(), name: "Duplicate")
        let secondTheme = Self.makeTheme(id: UUID(), name: "duplicate")

        let didAddFirstTheme = await store.add(firstTheme)
        let didAddSecondTheme = await store.add(secondTheme)

        XCTAssertTrue(didAddFirstTheme)
        XCTAssertFalse(didAddSecondTheme)

        XCTAssertEqual(store.themes, [firstTheme])
        XCTAssertEqual(store.lastError, "A theme named \"duplicate\" already exists.")
    }

    func testThemeExchangeDocumentRoundTripsSingleTheme() throws {
        let theme = Self.makeTheme(name: "Portable")
        let document = ThemeExchangeDocument(theme: theme)

        let decoded = try ThemeExchangeDocument(data: document.exportedData())

        XCTAssertEqual(decoded.themes, [theme])
    }

    func testThemeExchangeDocumentDecodesThemeBundle() throws {
        let firstTheme = Self.makeTheme(id: UUID(), name: "First")
        let secondTheme = Self.makeTheme(id: UUID(), name: "Second")
        let bundle = ThemeExchangeDocument(themes: [firstTheme, secondTheme])

        let decoded = try ThemeExchangeDocument(data: bundle.exportedData())

        XCTAssertEqual(decoded.themes, [firstTheme, secondTheme])
    }

    private func makeTemporaryThemeURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DownwardThemeStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appending(path: "themes.json")
    }

    private static func makeTheme(id: UUID = UUID(), name: String) -> CustomTheme {
        CustomTheme(
            id: id,
            name: name,
            background: HexColor(hex: "#1E1E1E"),
            text: HexColor(hex: "#D4D4D4"),
            tint: HexColor(hex: "#569CD6"),
            boldItalicMarker: HexColor(hex: "#72727F"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
    }
}
