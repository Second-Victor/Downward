import CoreText
import XCTest
@testable import Downward

final class ImportedFontManagerTests: XCTestCase {
    @MainActor
    func testImportFontCopiesMetadataAndPersistsRecord() async throws {
        let sourceURL = try makeTemporaryFontSource(named: "Readable.ttf")
        let fontsDirectory = try makeTemporaryFontsDirectory()
        let manager = ImportedFontManager(
            fontsDirectory: fontsDirectory,
            registerFont: { _ in .success },
            extractMetadata: { _ in
                Self.metadata(displayName: "Readable Regular", familyName: "Readable", postScriptName: "Readable-Regular")
            }
        )

        let importedRecord = await manager.importFont(from: sourceURL)
        let record = try XCTUnwrap(importedRecord)
        let reloadedManager = ImportedFontManager(
            fontsDirectory: fontsDirectory,
            registerFont: { _ in .success },
            extractMetadata: { _ in nil }
        )

        XCTAssertEqual(record.displayName, "Readable Regular")
        XCTAssertEqual(record.familyName, "Readable")
        XCTAssertEqual(record.postScriptName, "Readable-Regular")
        XCTAssertEqual(manager.records, [record])
        XCTAssertEqual(reloadedManager.records, [record])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fontsDirectory.appending(path: record.relativePath).path))
    }

    @MainActor
    func testImportFontAvoidsDuplicateRecordsByPostScriptName() async throws {
        let firstSourceURL = try makeTemporaryFontSource(named: "First.ttf")
        let secondSourceURL = try makeTemporaryFontSource(named: "Second.otf")
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                Self.metadata(displayName: "Duplicate Regular", familyName: "Duplicate", postScriptName: "Duplicate-Regular")
            }
        )

        let importedFirstRecord = await manager.importFont(from: firstSourceURL)
        let importedSecondRecord = await manager.importFont(from: secondSourceURL)
        let firstRecord = try XCTUnwrap(importedFirstRecord)
        let secondRecord = try XCTUnwrap(importedSecondRecord)

        XCTAssertEqual(firstRecord, secondRecord)
        XCTAssertEqual(manager.records, [firstRecord])
    }

    @MainActor
    func testImportFontsGroupsMultipleFacesByFamily() async throws {
        let regularURL = try makeTemporaryFontSource(named: "Family-Regular.ttf")
        let boldURL = try makeTemporaryFontSource(named: "Family-Bold.ttf")
        let italicURL = try makeTemporaryFontSource(named: "Family-Italic.otf")
        var metadataQueue = [
            Self.metadata(
                displayName: "Family Regular",
                familyName: "Family",
                postScriptName: "Family-Regular",
                styleName: "Regular"
            ),
            Self.metadata(
                displayName: "Family Bold",
                familyName: "Family",
                postScriptName: "Family-Bold",
                styleName: "Bold",
                traits: .traitBold
            ),
            Self.metadata(
                displayName: "Family Italic",
                familyName: "Family",
                postScriptName: "Family-Italic",
                styleName: "Italic",
                traits: .traitItalic
            )
        ]
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                metadataQueue.removeFirst()
            }
        )

        _ = await manager.importFonts(from: [regularURL, boldURL, italicURL])
        let family = try XCTUnwrap(manager.families.first)

        XCTAssertEqual(family.familyName, "Family")
        XCTAssertEqual(family.records.map(\.postScriptName).sorted(), ["Family-Bold", "Family-Italic", "Family-Regular"])
        XCTAssertEqual(family.baseRecord?.postScriptName, "Family-Regular")
        XCTAssertEqual(family.record(matching: .bold)?.postScriptName, "Family-Bold")
        XCTAssertEqual(family.record(matching: .italic)?.postScriptName, "Family-Italic")
        XCTAssertEqual(family.styleSummary, "3 styles")
    }

    @MainActor
    func testFamilyStyleSlotsOnlyReportMatchingInstalledFaces() async throws {
        let mediumURL = try makeTemporaryFontSource(named: "Family-Medium.ttf")
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                Self.metadata(
                    displayName: "Family Medium",
                    familyName: "Family",
                    postScriptName: "Family-Medium",
                    styleName: "Medium"
                )
            }
        )

        _ = await manager.importFont(from: mediumURL)
        let family = try XCTUnwrap(manager.families.first)

        XCTAssertNil(family.record(matching: .regular))
        XCTAssertNil(family.record(matching: .bold))
        XCTAssertNil(family.record(matching: .italic))
        XCTAssertEqual(family.baseRecord?.postScriptName, "Family-Medium")
    }

    @MainActor
    func testDeleteFamilyRemovesAllFaceFilesMetadataAndSelectionTargets() async throws {
        let regularURL = try makeTemporaryFontSource(named: "DeleteMe-Regular.ttf")
        let boldURL = try makeTemporaryFontSource(named: "DeleteMe-Bold.ttf")
        let fontsDirectory = try makeTemporaryFontsDirectory()
        var metadataQueue = [
            Self.metadata(
                displayName: "Delete Me Regular",
                familyName: "Delete Me",
                postScriptName: "DeleteMe-Regular",
                styleName: "Regular"
            ),
            Self.metadata(
                displayName: "Delete Me Bold",
                familyName: "Delete Me",
                postScriptName: "DeleteMe-Bold",
                styleName: "Bold",
                traits: .traitBold
            )
        ]
        var unregisteredURLs: [URL] = []
        let manager = ImportedFontManager(
            fontsDirectory: fontsDirectory,
            registerFont: { _ in .success },
            unregisterFont: { url in
                unregisteredURLs.append(url)
                return .success
            },
            extractMetadata: { _ in
                metadataQueue.removeFirst()
            }
        )

        let records = await manager.importFonts(from: [regularURL, boldURL])
        let importedFileURLs = records.map { fontsDirectory.appending(path: $0.relativePath) }
        let didDelete = manager.deleteFamily(named: "Delete Me")
        let reloadedManager = ImportedFontManager(
            fontsDirectory: fontsDirectory,
            registerFont: { _ in .success },
            unregisterFont: { _ in .success },
            extractMetadata: { _ in nil }
        )

        XCTAssertTrue(didDelete)
        XCTAssertTrue(manager.records.isEmpty)
        XCTAssertTrue(reloadedManager.records.isEmpty)
        XCTAssertEqual(Set(unregisteredURLs), Set(importedFileURLs))
        XCTAssertTrue(importedFileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) == false })
        XCTAssertNil(manager.lastError)
    }

    @MainActor
    func testRegisterAllFontsScansImportedFontsFolder() throws {
        let fontsDirectory = try makeTemporaryFontsDirectory()
        let fontURL = fontsDirectory.appending(path: "Existing.ttf")
        try Data("fake font".utf8).write(to: fontURL)
        var registeredURLs: [URL] = []
        let manager = ImportedFontManager(
            fontsDirectory: fontsDirectory,
            registerFont: { url in
                registeredURLs.append(url)
                return .success
            },
            extractMetadata: { _ in nil }
        )

        manager.registerAllFonts()

        XCTAssertEqual(registeredURLs, [fontURL])
    }

    @MainActor
    func testRegisterAllFontsIgnoresMissingFolderAndDeletedFiles() throws {
        let fontsDirectory = try makeTemporaryFontsDirectory()
        let manager = ImportedFontManager(
            fontsDirectory: fontsDirectory.appending(path: "Deleted", directoryHint: .isDirectory),
            registerFont: { _ in
                XCTFail("No font files should be registered from a missing folder.")
                return .success
            },
            extractMetadata: { _ in nil }
        )

        manager.registerAllFonts()

        XCTAssertTrue(manager.records.isEmpty)
    }

    @MainActor
    func testImportRejectsUnsupportedFileTypeWithUserMessage() async throws {
        let sourceURL = try makeTemporaryFontSource(named: "NotAFont.txt")
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                Self.metadata(displayName: "Ignored", familyName: "Ignored", postScriptName: "Ignored-Regular")
            }
        )

        let record = await manager.importFont(from: sourceURL)

        XCTAssertNil(record)
        XCTAssertEqual(manager.lastError, "Choose a .ttf or .otf font file.")
    }

    @MainActor
    func testSettingsImportHandlerDoesNothingWhenThemeUnlockIsMissing() async throws {
        let sourceURL = try makeTemporaryFontSource(named: "Locked.ttf")
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in
                XCTFail("Locked font imports should not register files.")
                return .success
            },
            extractMetadata: { _ in
                Self.metadata(displayName: "Locked", familyName: "Locked", postScriptName: "Locked-Regular")
            }
        )
        let store = EditorAppearanceStore(
            resolver: EditorFontResolver(isRuntimeFontAvailable: { $0 == "Locked-Regular" }),
            initialPreferences: .default
        )

        await ImportedFontSettingsImportHandler.handle(
            result: .success([sourceURL]),
            importedFontManager: manager,
            editorAppearanceStore: store,
            hasUnlockedThemes: false
        )

        XCTAssertTrue(manager.records.isEmpty)
        XCTAssertNil(manager.lastError)
        XCTAssertNil(store.selectedImportedFontFamilyName)
    }

    @MainActor
    func testSettingsImportHandlerSelectsImportedFontFamilyForUnlockedUsers() async throws {
        let sourceURL = try makeTemporaryFontSource(named: "Unlocked.otf")
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                Self.metadata(displayName: "Unlocked Regular", familyName: "Unlocked", postScriptName: "Unlocked-Regular")
            }
        )
        let store = EditorAppearanceStore(
            resolver: EditorFontResolver(isRuntimeFontAvailable: { $0 == "Unlocked-Regular" }),
            initialPreferences: .default
        )
        store.setImportedFontsUnlocked(true)

        await ImportedFontSettingsImportHandler.handle(
            result: .success([sourceURL]),
            importedFontManager: manager,
            editorAppearanceStore: store,
            hasUnlockedThemes: true
        )

        XCTAssertEqual(manager.records.map(\.postScriptName), ["Unlocked-Regular"])
        XCTAssertEqual(store.selectedImportedFontFamilyName, "Unlocked")
    }

    @MainActor
    func testSettingsImportHandlerInstallsMissingStyleIntoExistingFamily() async throws {
        let regularURL = try makeTemporaryFontSource(named: "Family-Regular.ttf")
        let boldURL = try makeTemporaryFontSource(named: "Family-Bold.ttf")
        var metadataQueue = [
            Self.metadata(
                displayName: "Family Regular",
                familyName: "Family",
                postScriptName: "Family-Regular",
                styleName: "Regular"
            ),
            Self.metadata(
                displayName: "Family Bold",
                familyName: "Family",
                postScriptName: "Family-Bold",
                styleName: "Bold",
                traits: .traitBold
            )
        ]
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                metadataQueue.removeFirst()
            }
        )
        let store = EditorAppearanceStore(
            resolver: EditorFontResolver(isRuntimeFontAvailable: {
                ["Family-Regular", "Family-Bold"].contains($0)
            }),
            initialPreferences: .default
        )
        store.setImportedFontsUnlocked(true)
        _ = await manager.importFont(from: regularURL)

        await ImportedFontSettingsImportHandler.handle(
            result: .success([boldURL]),
            importedFontManager: manager,
            editorAppearanceStore: store,
            hasUnlockedThemes: true,
            target: .familyStyle(familyName: "Family", style: .bold)
        )

        let family = try XCTUnwrap(manager.family(named: "Family"))
        XCTAssertEqual(family.record(matching: .bold)?.postScriptName, "Family-Bold")
        XCTAssertEqual(store.selectedImportedFontFamilyName, "Family")
        XCTAssertNil(manager.lastError)
    }

    @MainActor
    func testSettingsImportHandlerReportsWhenImportedFileDoesNotFillMissingStyle() async throws {
        let regularURL = try makeTemporaryFontSource(named: "Family-Regular.ttf")
        let otherURL = try makeTemporaryFontSource(named: "Other-Regular.ttf")
        var metadataQueue = [
            Self.metadata(
                displayName: "Family Regular",
                familyName: "Family",
                postScriptName: "Family-Regular",
                styleName: "Regular"
            ),
            Self.metadata(
                displayName: "Other Regular",
                familyName: "Other",
                postScriptName: "Other-Regular",
                styleName: "Regular"
            )
        ]
        let manager = ImportedFontManager(
            fontsDirectory: try makeTemporaryFontsDirectory(),
            registerFont: { _ in .success },
            extractMetadata: { _ in
                metadataQueue.removeFirst()
            }
        )
        let store = EditorAppearanceStore(
            resolver: EditorFontResolver(isRuntimeFontAvailable: { _ in true }),
            initialPreferences: .default
        )
        store.setImportedFontsUnlocked(true)
        _ = await manager.importFont(from: regularURL)

        await ImportedFontSettingsImportHandler.handle(
            result: .success([otherURL]),
            importedFontManager: manager,
            editorAppearanceStore: store,
            hasUnlockedThemes: true,
            target: .familyStyle(familyName: "Family", style: .bold)
        )

        XCTAssertEqual(manager.lastError, "That file was imported, but it did not add Bold to Family.")
    }

    private func makeTemporaryFontsDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DownwardImportedFontsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func makeTemporaryFontSource(named fileName: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DownwardImportedFontsSource-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appending(path: fileName)
        try Data("fake font".utf8).write(to: fileURL)
        return fileURL
    }

    private static func metadata(
        displayName: String,
        familyName: String,
        postScriptName: String,
        styleName: String = "Regular",
        traits: CTFontSymbolicTraits = []
    ) -> ImportedFontMetadata {
        ImportedFontMetadata(
            displayName: displayName,
            familyName: familyName,
            postScriptName: postScriptName,
            styleName: styleName,
            symbolicTraitsRawValue: traits.rawValue
        )
    }
}
