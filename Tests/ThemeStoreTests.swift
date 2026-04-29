import XCTest
@testable import Downward

final class ThemeStoreTests: XCTestCase {
    @MainActor
    func testThemeStoreAddsAndPersistsCustomTheme() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = makeThemeStore(fileURL: fileURL)
        let theme = Self.makeTheme(name: "Night Writing")

        let didAdd = await store.add(theme)
        XCTAssertTrue(didAdd)

        let reloadedStore = makeThemeStore(fileURL: fileURL)
        await reloadedStore.waitForInitialLoad()

        XCTAssertEqual(reloadedStore.themes, [theme])
        XCTAssertEqual(reloadedStore.resolve(theme.id.uuidString).label, "Night Writing")
    }

    @MainActor
    func testThemeStoreListsBundledPremiumThemesBehindUnlock() async throws {
        let store = makeThemeStore(
            fileURL: try makeTemporaryThemeURL(),
            hasUnlockedThemes: false,
            bundledPremiumThemes: ThemeStore.bundledPremiumThemes
        )
        await store.waitForInitialLoad()

        XCTAssertEqual(store.themes, ThemeStore.bundledPremiumThemes)
        XCTAssertEqual(
            store.themes.map(\.name),
            [
                "Monokai Light",
                "Monokai",
                "Solarized",
                "OLED Midnight",
                "Sepia Paper",
                "Forest",
                "Polar Night"
            ]
        )

        let monokai = try XCTUnwrap(store.themes.last)
        XCTAssertFalse(store.canSelectTheme(withID: monokai.id.uuidString))
        XCTAssertEqual(store.resolve(monokai.id.uuidString), .adaptive)
    }

    @MainActor
    func testThemeStoreKeepsBundledPremiumThemeEditsAcrossReload() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let bundledTheme = Self.makeTheme(name: "Bundled Original")
        let store = makeThemeStore(
            fileURL: fileURL,
            bundledPremiumThemes: [bundledTheme]
        )
        await store.waitForInitialLoad()

        var editedTheme = bundledTheme
        editedTheme.name = "Edited Bundled"
        let didUpdate = await store.update(editedTheme)

        let reloadedStore = makeThemeStore(
            fileURL: fileURL,
            bundledPremiumThemes: [bundledTheme]
        )
        await reloadedStore.waitForInitialLoad()

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(store.themes, [editedTheme])
        XCTAssertEqual(reloadedStore.themes, [editedTheme])
        XCTAssertEqual(reloadedStore.resolve(editedTheme.id.uuidString).label, "Edited Bundled")
    }

    @MainActor
    func testThemeStoreDoesNotDeleteBundledPremiumThemes() async throws {
        let bundledTheme = Self.makeTheme(name: "Bundled")
        let store = makeThemeStore(
            fileURL: try makeTemporaryThemeURL(),
            bundledPremiumThemes: [bundledTheme]
        )
        await store.waitForInitialLoad()

        let didDelete = await store.delete(id: bundledTheme.id)

        XCTAssertFalse(didDelete)
        XCTAssertEqual(store.themes, [bundledTheme])
        XCTAssertFalse(store.canDeleteTheme(id: bundledTheme.id))
        XCTAssertEqual(store.lastError, "Bundled Extra Themes cannot be deleted.")
    }

    @MainActor
    func testThemeStoreDeletesUserAddedThemes() async throws {
        let store = makeThemeStore(fileURL: try makeTemporaryThemeURL())
        let userTheme = Self.makeTheme(name: "User Theme")

        let didAdd = await store.add(userTheme)
        let canDelete = store.canDeleteTheme(id: userTheme.id)
        let didDelete = await store.delete(id: userTheme.id)

        XCTAssertTrue(didAdd)
        XCTAssertTrue(canDelete)
        XCTAssertTrue(didDelete)
        XCTAssertTrue(store.themes.isEmpty)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testThemeStoreRejectsDuplicateCustomThemeNames() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = makeThemeStore(fileURL: fileURL)
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
        let store = makeThemeStore(fileURL: fileURL)
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
        let store = makeThemeStore(fileURL: fileURL)
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

    @MainActor
    func testThemeStoreImportAddsAllThemesFromExplicitImport() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = makeThemeStore(fileURL: fileURL)
        let firstTheme = Self.makeTheme(id: UUID(), name: "Bundle One")
        let secondTheme = Self.makeTheme(id: UUID(), name: "Bundle Two")

        let didImport = await store.importThemes([firstTheme, secondTheme])

        XCTAssertTrue(didImport)
        XCTAssertEqual(store.themes, [firstTheme, secondTheme])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testThemeStoreSerializesOverlappingExplicitMutations() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let recorder = DelayedThemePersistenceRecorder()
        let firstTheme = Self.makeTheme(id: UUID(), name: "First")
        let secondTheme = Self.makeTheme(id: UUID(), name: "Second")
        let store = makeThemeStore(
            fileURL: fileURL,
            persistThemes: { themes, fileURL in
                try await recorder.persist(themes, to: fileURL)
            }
        )

        async let didAddFirst = store.add(firstTheme)
        try await Task.sleep(for: .milliseconds(20))
        async let didAddSecond = store.add(secondTheme)

        let results = await (didAddFirst, didAddSecond)
        let persistedThemeNames = await recorder.persistedThemeNames
        let reloadedStore = makeThemeStore(fileURL: fileURL)
        await reloadedStore.waitForInitialLoad()

        XCTAssertEqual(results.0, true)
        XCTAssertEqual(results.1, true)
        XCTAssertEqual(persistedThemeNames, [["First"], ["First", "Second"]])
        XCTAssertEqual(store.themes, [firstTheme, secondTheme])
        XCTAssertEqual(reloadedStore.themes, [firstTheme, secondTheme])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testThemeStoreSerializesExplicitImportsWithOtherMutations() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let recorder = DelayedThemePersistenceRecorder()
        let importedTheme = Self.makeTheme(id: UUID(), name: "Imported")
        let manualTheme = Self.makeTheme(id: UUID(), name: "Manual")
        let store = makeThemeStore(
            fileURL: fileURL,
            persistThemes: { themes, fileURL in
                try await recorder.persist(themes, to: fileURL)
            }
        )

        async let didImport = store.importThemes([importedTheme])
        try await Task.sleep(for: .milliseconds(20))
        async let didAdd = store.add(manualTheme)

        let results = await (didImport, didAdd)
        let persistedThemeNames = await recorder.persistedThemeNames
        let reloadedStore = makeThemeStore(fileURL: fileURL)
        await reloadedStore.waitForInitialLoad()

        XCTAssertEqual(results.0, true)
        XCTAssertEqual(results.1, true)
        XCTAssertEqual(persistedThemeNames, [["Imported"], ["Imported", "Manual"]])
        XCTAssertEqual(store.themes, [importedTheme, manualTheme])
        XCTAssertEqual(reloadedStore.themes, [importedTheme, manualTheme])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testSettingsImportHandlerLoadsSelectedFileAndImportsThroughThemeStore() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = makeThemeStore(fileURL: fileURL)
        await store.waitForInitialLoad()
        let selectedURL = fileURL.deletingLastPathComponent().appending(path: "SelectedTheme.json")
        let theme = Self.makeTheme(id: UUID(), name: "Settings Import")
        let recorder = ThemeImportLoadRecorder(themes: [theme])

        await ThemeSettingsImportHandler.handle(
            result: .success(selectedURL),
            themeStore: store
        ) { url in
            try await recorder.load(from: url)
        }

        let loadedURLs = await recorder.recordedLoadedURLs()

        XCTAssertEqual(loadedURLs, [selectedURL])
        XCTAssertEqual(store.themes, [theme])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testSettingsImportHandlerIgnoresUserCancellation() async throws {
        let fileURL = try makeTemporaryThemeURL()
        let store = makeThemeStore(fileURL: fileURL)
        await store.waitForInitialLoad()
        let cancellationError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.userCancelled.rawValue,
            userInfo: nil
        )

        await ThemeSettingsImportHandler.handle(
            result: .failure(cancellationError),
            themeStore: store
        ) { _ in
            []
        }

        XCTAssertTrue(store.themes.isEmpty)
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

    func testThemeExchangeDocumentRejectsNonThemeJSONObjectWithUserReadableError() {
        let data = """
        {
          "name" : "Not a theme",
          "kind" : "ordinary workspace JSON"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ThemeExchangeDocument(data: data)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected JSON file is not a valid Downward theme export."
            )
        }
    }

    func testThemeExchangeDocumentRejectsEmptyArrayWithUserReadableError() {
        let data = Data("[]".utf8)

        XCTAssertThrowsError(try ThemeExchangeDocument(data: data)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected JSON file is not a valid Downward theme export."
            )
        }
    }

    func testThemeExchangeDocumentRejectsEmptyBundleWithUserReadableError() {
        let data = """
        {
          "themes" : []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ThemeExchangeDocument(data: data)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected JSON file is not a valid Downward theme export."
            )
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

    @MainActor
    func testLockedThemeStoreRejectsCustomThemeCreation() async throws {
        let store = makeThemeStore(fileURL: try makeTemporaryThemeURL(), hasUnlockedThemes: false)
        let theme = Self.makeTheme(name: "Locked")

        let didAdd = await store.add(theme)

        XCTAssertFalse(didAdd)
        XCTAssertTrue(store.themes.isEmpty)
        XCTAssertEqual(store.lastError, ThemeEntitlementGate.lockedMessage)
    }

    @MainActor
    func testLockedThemeStoreRejectsCustomThemeEditing() async throws {
        let entitlements = ThemeEntitlementStore(hasUnlockedThemes: true)
        let store = makeThemeStore(fileURL: try makeTemporaryThemeURL(), entitlements: entitlements)
        let theme = Self.makeTheme(id: UUID(), name: "Original")
        let updatedTheme = Self.makeTheme(id: theme.id, name: "Updated")

        let didAddTheme = await store.add(theme)
        XCTAssertTrue(didAddTheme)
        entitlements.setHasUnlockedThemes(false)

        let didUpdate = await store.update(updatedTheme)

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(store.themes, [theme])
        XCTAssertEqual(store.lastError, ThemeEntitlementGate.lockedMessage)
    }

    @MainActor
    func testLockedThemeStoreRejectsCustomThemeImport() async throws {
        let store = makeThemeStore(fileURL: try makeTemporaryThemeURL(), hasUnlockedThemes: false)
        let importedTheme = Self.makeTheme(name: "Imported")

        let didImport = await store.importThemes([importedTheme])

        XCTAssertFalse(didImport)
        XCTAssertTrue(store.themes.isEmpty)
        XCTAssertEqual(store.lastError, ThemeEntitlementGate.lockedMessage)
    }

    @MainActor
    func testLockedThemeStoreResolvesSelectedCustomThemeToAdaptive() async throws {
        let entitlements = ThemeEntitlementStore(hasUnlockedThemes: true)
        let store = makeThemeStore(fileURL: try makeTemporaryThemeURL(), entitlements: entitlements)
        let theme = Self.makeTheme(name: "Locked Later")

        let didAddTheme = await store.add(theme)
        XCTAssertTrue(didAddTheme)
        entitlements.setHasUnlockedThemes(false)

        XCTAssertEqual(store.resolve(theme.id.uuidString), .adaptive)
        XCTAssertFalse(store.canSelectTheme(withID: theme.id.uuidString))
        XCTAssertTrue(store.canSelectTheme(withID: EditorTheme.adaptive.id))
    }

    @MainActor
    func testSettingsImportHandlerDoesNotLoadFileWhenThemesAreLocked() async throws {
        let store = makeThemeStore(fileURL: try makeTemporaryThemeURL(), hasUnlockedThemes: false)
        let selectedURL = URL(filePath: "/tmp/LockedTheme.json")
        let recorder = ThemeImportLoadRecorder(themes: [Self.makeTheme(name: "Should Not Load")])

        await ThemeSettingsImportHandler.handle(
            result: .success(selectedURL),
            themeStore: store,
            hasUnlockedThemes: false
        ) { url in
            try await recorder.load(from: url)
        }

        let loadedURLs = await recorder.recordedLoadedURLs()

        XCTAssertTrue(loadedURLs.isEmpty)
        XCTAssertTrue(store.themes.isEmpty)
        XCTAssertEqual(store.lastError, ThemeEntitlementGate.lockedMessage)
    }

    @MainActor
    func testThemeEntitlementGateCoversCustomThemeEntryPoints() {
        XCTAssertFalse(ThemeEntitlementGate.canCreateCustomTheme(hasUnlockedThemes: false))
        XCTAssertFalse(ThemeEntitlementGate.canImportCustomThemes(hasUnlockedThemes: false))
        XCTAssertFalse(ThemeEntitlementGate.canEditCustomThemes(hasUnlockedThemes: false))
        XCTAssertFalse(ThemeEntitlementGate.canExportCustomThemes(hasUnlockedThemes: false))
        XCTAssertFalse(ThemeEntitlementGate.canSelectCustomTheme(hasUnlockedThemes: false))

        XCTAssertTrue(ThemeEntitlementGate.canCreateCustomTheme(hasUnlockedThemes: true))
        XCTAssertTrue(ThemeEntitlementGate.canImportCustomThemes(hasUnlockedThemes: true))
        XCTAssertTrue(ThemeEntitlementGate.canEditCustomThemes(hasUnlockedThemes: true))
        XCTAssertTrue(ThemeEntitlementGate.canExportCustomThemes(hasUnlockedThemes: true))
        XCTAssertTrue(ThemeEntitlementGate.canSelectCustomTheme(hasUnlockedThemes: true))
    }

    @MainActor
    private func makeThemeStore(
        fileURL: URL,
        persistThemes: ThemeStore.PersistThemes? = nil,
        hasUnlockedThemes: Bool = true,
        entitlements: ThemeEntitlementStore? = nil,
        bundledPremiumThemes: [CustomTheme] = []
    ) -> ThemeStore {
        ThemeStore(
            fileURL: fileURL,
            persistThemes: persistThemes,
            entitlements: entitlements ?? ThemeEntitlementStore(hasUnlockedThemes: hasUnlockedThemes),
            bundledPremiumThemes: bundledPremiumThemes
        )
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

private actor DelayedThemePersistenceRecorder {
    private(set) var persistedThemeNames: [[String]] = []
    private var persistCount = 0

    func persist(_ themes: [CustomTheme], to fileURL: URL) async throws {
        persistCount += 1
        if persistCount == 1 {
            try await Task.sleep(for: .milliseconds(80))
        }

        persistedThemeNames.append(themes.map(\.name))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(themes).write(to: fileURL, options: .atomic)
    }
}

private actor ThemeImportLoadRecorder {
    private var loadedURLs: [URL] = []
    private let themes: [CustomTheme]

    init(themes: [CustomTheme]) {
        self.themes = themes
    }

    func load(from url: URL) async throws -> [CustomTheme] {
        loadedURLs.append(url)
        return themes
    }

    func recordedLoadedURLs() -> [URL] {
        loadedURLs
    }
}
