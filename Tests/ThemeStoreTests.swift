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

    @MainActor
    func testThemeStoreImportRejectsDuplicateThemeNamesWithUserReadableError() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = ThemeStore(fileURL: fileURL)
        let existingTheme = Self.makeTheme(id: UUID(), name: "Duplicate")
        let importedTheme = Self.makeTheme(id: UUID(), name: "duplicate")

        let didAddExistingTheme = await store.add(existingTheme)
        XCTAssertTrue(didAddExistingTheme)

        let didImport = await store.importThemes([importedTheme])

        XCTAssertFalse(didImport)
        XCTAssertEqual(store.themes, [existingTheme])
        XCTAssertEqual(
            store.lastError,
            "Could not import \"duplicate\" because a different theme with that name already exists."
        )
    }

    @MainActor
    func testThemeStoreImportReplacesExistingThemeWithMatchingID() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = ThemeStore(fileURL: fileURL)
        let themeID = UUID()
        let originalTheme = Self.makeTheme(id: themeID, name: "Original")
        let importedReplacement = Self.makeTheme(id: themeID, name: "Replacement")

        let didAddOriginalTheme = await store.add(originalTheme)
        XCTAssertTrue(didAddOriginalTheme)

        let didImport = await store.importThemes([importedReplacement])

        XCTAssertTrue(didImport)
        XCTAssertEqual(store.themes, [importedReplacement])
        XCTAssertNil(store.lastError)
    }

    func testThemeExchangeDocumentRoundTripsSingleTheme() throws {
        let theme = Self.makeTheme(name: "Portable")
        let document = ThemeExchangeDocument(theme: theme)

        let decoded = try ThemeExchangeDocument(data: document.exportedData())

        XCTAssertEqual(decoded.themes, [theme])
    }

    func testThemeExchangeDocumentDecodesPrototypeThemeWithStrikethroughColor() throws {
        let data = """
        {
          "horizontalRule" : "#FF9414",
          "text" : "#231D21",
          "tint" : "#379FD2",
          "checkboxChecked" : "#2BA34C",
          "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
          "inlineCode" : "#382E34",
          "codeBackground" : "#E3DDDD",
          "checkboxUnchecked" : "#D83F3F",
          "strikethrough" : "#563FC1",
          "name" : "Monokai Light",
          "boldItalicMarker" : "#E25B75",
          "background" : "#F2EDEC"
        }
        """.data(using: .utf8)!

        let decoded = try ThemeExchangeDocument(data: data)

        XCTAssertEqual(decoded.themes.count, 1)
        XCTAssertEqual(decoded.themes.first?.name, "Monokai Light")
        XCTAssertEqual(decoded.themes.first?.strikethrough, HexColor(hex: "#563FC1"))
    }

    func testThemeExchangeDocumentDecodesLegacyThemeWithoutStrikethroughColor() throws {
        let data = """
        {
          "horizontalRule" : "#404040",
          "text" : "#D4D4D4",
          "tint" : "#569CD6",
          "checkboxChecked" : "#6A9955",
          "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
          "inlineCode" : "#CE9178",
          "codeBackground" : "#2D2D2D",
          "checkboxUnchecked" : "#F44747",
          "name" : "Legacy",
          "boldItalicMarker" : "#72727F",
          "background" : "#1E1E1E"
        }
        """.data(using: .utf8)!

        let decoded = try ThemeExchangeDocument(data: data)

        XCTAssertEqual(decoded.themes.count, 1)
        XCTAssertEqual(decoded.themes.first?.name, "Legacy")
        XCTAssertEqual(decoded.themes.first?.strikethrough.hex.count, 9)
    }

    func testThemeExchangeDocumentDecodesThemeBundle() throws {
        let firstTheme = Self.makeTheme(id: UUID(), name: "First")
        let secondTheme = Self.makeTheme(id: UUID(), name: "Second")
        let bundle = ThemeExchangeDocument(themes: [firstTheme, secondTheme])

        let decoded = try ThemeExchangeDocument(data: bundle.exportedData())

        XCTAssertEqual(decoded.themes, [firstTheme, secondTheme])
    }

    func testThemeExchangeDocumentRejectsUnsupportedFutureSchemaVersion() {
        let data = """
        {
          "schemaVersion" : 999,
          "horizontalRule" : "#404040",
          "text" : "#D4D4D4",
          "tint" : "#569CD6",
          "checkboxChecked" : "#6A9955",
          "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
          "inlineCode" : "#CE9178",
          "codeBackground" : "#2D2D2D",
          "checkboxUnchecked" : "#F44747",
          "name" : "Future",
          "boldItalicMarker" : "#72727F",
          "background" : "#1E1E1E"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ThemeExchangeDocument(data: data)) { error in
            XCTAssertEqual(
                error as? ThemeSchemaVersionError,
                .unsupported(schemaVersion: 999, maximumSupportedVersion: CustomTheme.currentSchemaVersion)
            )
        }
    }

    func testThemeExchangeDocumentRejectsInvalidJSONWithUserReadableError() {
        let data = Data("{".utf8)

        XCTAssertThrowsError(try ThemeExchangeDocument(data: data)) { error in
            let localizedError = error as? LocalizedError
            XCTAssertEqual(localizedError?.errorDescription, "The selected file is not valid JSON.")
        }
    }

    func testThemeImportServiceLoadsThemeJSONFromFileURL() async throws {
        let theme = Self.makeTheme(name: "Workspace Theme")
        let document = ThemeExchangeDocument(theme: theme)
        let themeURL = try makeTemporaryThemeURL()
        try document.exportedData().write(to: themeURL)

        let importedThemes = try await ThemeImportService().loadThemes(from: themeURL)

        XCTAssertEqual(importedThemes, [theme])
    }

    func testThemeImportServiceLoadsThemeArrayFromFileURL() async throws {
        let firstTheme = Self.makeTheme(id: UUID(), name: "Array One")
        let secondTheme = Self.makeTheme(id: UUID(), name: "Array Two")
        let document = ThemeExchangeDocument(themes: [firstTheme, secondTheme])
        let themeURL = try makeTemporaryThemeURL()
        try document.exportedData().write(to: themeURL)

        let importedThemes = try await ThemeImportService().loadThemes(from: themeURL)

        XCTAssertEqual(importedThemes, [firstTheme, secondTheme])
    }

    func testThemeImportServiceLoadsThemeBundleFromFileURL() async throws {
        let firstThemeID = UUID()
        let secondThemeID = UUID()
        let firstTheme = Self.makeTheme(id: firstThemeID, name: "Bundle One")
        let secondTheme = Self.makeTheme(id: secondThemeID, name: "Bundle Two")
        let themeURL = try makeTemporaryThemeURL()
        let data = """
        {
          "themes" : [
            {
              "schemaVersion" : 2,
              "horizontalRule" : "#404040",
              "text" : "#D4D4D4",
              "tint" : "#569CD6",
              "checkboxChecked" : "#6A9955",
              "id" : "\(firstThemeID.uuidString)",
              "inlineCode" : "#CE9178",
              "codeBackground" : "#2D2D2D",
              "checkboxUnchecked" : "#F44747",
              "strikethrough" : "#808080",
              "name" : "Bundle One",
              "boldItalicMarker" : "#72727F",
              "background" : "#1E1E1E"
            },
            {
              "schemaVersion" : 2,
              "horizontalRule" : "#404040",
              "text" : "#D4D4D4",
              "tint" : "#569CD6",
              "checkboxChecked" : "#6A9955",
              "id" : "\(secondThemeID.uuidString)",
              "inlineCode" : "#CE9178",
              "codeBackground" : "#2D2D2D",
              "checkboxUnchecked" : "#F44747",
              "strikethrough" : "#808080",
              "name" : "Bundle Two",
              "boldItalicMarker" : "#72727F",
              "background" : "#1E1E1E"
            }
          ]
        }
        """.data(using: .utf8)!
        try data.write(to: themeURL)

        let importedThemes = try await ThemeImportService().loadThemes(from: themeURL)

        XCTAssertEqual(importedThemes, [firstTheme, secondTheme])
    }

    func testThemeImportServiceRejectsUnsupportedFutureSchemaVersionFromFileURL() async throws {
        let themeURL = try makeTemporaryThemeURL()
        let data = """
        {
          "schemaVersion" : 999,
          "horizontalRule" : "#404040",
          "text" : "#D4D4D4",
          "tint" : "#569CD6",
          "checkboxChecked" : "#6A9955",
          "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
          "inlineCode" : "#CE9178",
          "codeBackground" : "#2D2D2D",
          "checkboxUnchecked" : "#F44747",
          "name" : "Future",
          "boldItalicMarker" : "#72727F",
          "background" : "#1E1E1E"
        }
        """.data(using: .utf8)!
        try data.write(to: themeURL)

        do {
            _ = try await ThemeImportService().loadThemes(from: themeURL)
            XCTFail("Expected unsupported schema version to fail import")
        } catch let error as ThemeSchemaVersionError {
            XCTAssertEqual(
                error,
                .unsupported(schemaVersion: 999, maximumSupportedVersion: CustomTheme.currentSchemaVersion)
            )
            XCTAssertEqual(
                error.localizedDescription,
                "This theme uses schema version 999, but Downward supports up to version 2."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThemeImportServiceRejectsInvalidJSONFromFileURL() async throws {
        let themeURL = try makeTemporaryThemeURL()
        try Data("{".utf8).write(to: themeURL)

        do {
            _ = try await ThemeImportService().loadThemes(from: themeURL)
            XCTFail("Expected invalid JSON to fail import")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The selected file is not valid JSON.")
        }
    }

    func testThemeImportServiceLoadsLegacyThemeWithoutNewerOptionalFields() async throws {
        let themeURL = try makeTemporaryThemeURL()
        let data = """
        {
          "horizontalRule" : "#404040",
          "text" : "#D4D4D4",
          "tint" : "#569CD6",
          "checkboxChecked" : "#6A9955",
          "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
          "inlineCode" : "#CE9178",
          "codeBackground" : "#2D2D2D",
          "checkboxUnchecked" : "#F44747",
          "name" : "Legacy",
          "boldItalicMarker" : "#72727F",
          "background" : "#1E1E1E"
        }
        """.data(using: .utf8)!
        try data.write(to: themeURL)

        let importedThemes = try await ThemeImportService().loadThemes(from: themeURL)

        XCTAssertEqual(importedThemes.count, 1)
        XCTAssertEqual(importedThemes.first?.name, "Legacy")
        XCTAssertEqual(importedThemes.first?.strikethrough.hex.count, 9)
    }

    func testThemeImportServiceRejectsOversizedFileFromFileURL() async throws {
        let themeURL = try makeTemporaryThemeURL()
        let fileData = Data(repeating: 0x41, count: 2_621_440)
        try fileData.write(to: themeURL)

        do {
            _ = try await ThemeImportService(maximumFileSize: 1_048_576).loadThemes(from: themeURL)
            XCTFail("Expected oversized file import to fail")
        } catch let error as ThemeImportError {
            XCTAssertEqual(
                error,
                .fileTooLarge(actualFileSize: 2_621_440, maximumFileSize: 1_048_576)
            )
            XCTAssertEqual(
                error.localizedDescription,
                "The selected file is 2.5 MB, which exceeds the 1.0 MB import limit."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThemeExchangeDocumentRejectsInvalidThemeInsideArrayWithUserReadableError() throws {
        let data = """
        [
          {
            "schemaVersion" : 2,
            "horizontalRule" : "#404040",
            "text" : "#D4D4D4",
            "tint" : "#569CD6",
            "checkboxChecked" : "#6A9955",
            "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
            "inlineCode" : "#CE9178",
            "codeBackground" : "#2D2D2D",
            "checkboxUnchecked" : "#F44747",
            "name" : "Valid",
            "boldItalicMarker" : "#72727F",
            "background" : "#1E1E1E"
          },
          {
            "schemaVersion" : 2,
            "horizontalRule" : "#404040",
            "text" : "#D4D4D4",
            "tint" : "#569CD6",
            "checkboxChecked" : "#6A9955",
            "id" : "22019126-7DF8-475F-B132-A53F46EDAE89",
            "inlineCode" : "#CE9178",
            "codeBackground" : "#2D2D2D",
            "checkboxUnchecked" : "#F44747",
            "name" : "Broken",
            "boldItalicMarker" : "#72727F",
            "background" : "#NOTHEX"
          }
        ]
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ThemeExchangeDocument(data: data)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "One of the themes in this import file is invalid at themes[1].background. Hex colours may only contain hexadecimal digits."
            )
        }
    }

    func testThemeImportServiceRejectsInvalidThemeInsideBundleWithUserReadableError() async throws {
        let themeURL = try makeTemporaryThemeURL()
        let data = """
        {
          "themes" : [
            {
              "schemaVersion" : 2,
              "horizontalRule" : "#404040",
              "text" : "#D4D4D4",
              "tint" : "#569CD6",
              "checkboxChecked" : "#6A9955",
              "id" : "11019126-7DF8-475F-B132-A53F46EDAE89",
              "inlineCode" : "#CE9178",
              "codeBackground" : "#2D2D2D",
              "checkboxUnchecked" : "#F44747",
              "name" : "Valid",
              "boldItalicMarker" : "#72727F",
              "background" : "#1E1E1E"
            },
            {
              "schemaVersion" : 2,
              "horizontalRule" : "#404040",
              "text" : "#D4D4D4",
              "tint" : "#569CD6",
              "checkboxChecked" : "#6A9955",
              "id" : "22019126-7DF8-475F-B132-A53F46EDAE89",
              "inlineCode" : "#CE9178",
              "codeBackground" : "#2D2D2D",
              "checkboxUnchecked" : "#F44747",
              "name" : "Broken",
              "boldItalicMarker" : "#72727F",
              "background" : "#NOTHEX"
            }
          ]
        }
        """.data(using: .utf8)!
        try data.write(to: themeURL)

        do {
            _ = try await ThemeImportService().loadThemes(from: themeURL)
            XCTFail("Expected invalid bundled theme import to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "One of the themes in this import file is invalid at themes[1].background. Hex colours may only contain hexadecimal digits."
            )
        }
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
            strikethrough: HexColor(hex: "#808080"),
            inlineCode: HexColor(hex: "#CE9178"),
            codeBackground: HexColor(hex: "#2D2D2D"),
            horizontalRule: HexColor(hex: "#404040"),
            checkboxUnchecked: HexColor(hex: "#F44747"),
            checkboxChecked: HexColor(hex: "#6A9955")
        )
    }
}
