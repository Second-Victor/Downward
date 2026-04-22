import Foundation
import SwiftUI
import XCTest
@testable import Downward

final class EditorAutosaveTests: XCTestCase {
    @MainActor
    func testLiveDocumentManagerAutosavesSequentialEditsWithoutConflict() async throws {
        let fixture = try makeLiveDocumentFixture(
            named: "Sequential.md",
            contents: "# Entry\n\nOriginal text."
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let liveManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await liveManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let system = makeEditorSystem(
            documentManager: liveManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("# Entry\n\nFirst autosave.")
        try await Task.sleep(for: .milliseconds(120))
        system.viewModel.handleTextChange("# Entry\n\nSecond autosave.")
        try await Task.sleep(for: .milliseconds(120))
        system.viewModel.handleTextChange("# Entry\n\nFinal autosave.")
        try await waitUntil {
            system.session.openDocument?.text == "# Entry\n\nFinal autosave."
                && system.session.openDocument?.isDirty == false
        }

        XCTAssertEqual(system.session.openDocument?.text, "# Entry\n\nFinal autosave.")
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertFalse(system.viewModel.isShowingConflictResolution)
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
        XCTAssertEqual(
            try String(contentsOf: fixture.fileURL, encoding: .utf8),
            "# Entry\n\nFinal autosave."
        )
    }

    @MainActor
    func testLiveDocumentManagerDoesNotConflictWhenTypingAcrossDelayedAutosaves() async throws {
        let fixture = try makeLiveDocumentFixture(
            named: "Delayed.md",
            contents: "# Entry\n\nOriginal text."
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let baseManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await baseManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let delayedManager = DelayedLiveDocumentManager(
            base: baseManager,
            saveDelay: .milliseconds(120)
        )
        let system = makeEditorSystem(
            documentManager: delayedManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("# Entry\n\nFirst revision.")
        try await Task.sleep(for: .milliseconds(40))
        system.viewModel.handleTextChange("# Entry\n\nSecond revision.")
        try await Task.sleep(for: .milliseconds(70))
        system.viewModel.handleTextChange("# Entry\n\nThird revision.")
        try await waitUntil {
            system.session.openDocument?.text == "# Entry\n\nThird revision."
                && system.session.openDocument?.isDirty == false
        }

        XCTAssertEqual(system.session.openDocument?.text, "# Entry\n\nThird revision.")
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertFalse(system.viewModel.isShowingConflictResolution)
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
        XCTAssertEqual(
            try String(contentsOf: fixture.fileURL, encoding: .utf8),
            "# Entry\n\nThird revision."
        )
    }

    @MainActor
    func testLiveDocumentManagerForegroundRevalidationDoesNotConflictAfterOwnAutosave() async throws {
        let fixture = try makeLiveDocumentFixture(
            named: "Foreground.md",
            contents: "# Entry\n\nOriginal text."
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let liveManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await liveManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let system = makeEditorSystem(
            documentManager: liveManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("# Entry\n\nAutosaved text.")
        try await Task.sleep(for: .milliseconds(140))

        await system.coordinator.handleSceneDidBecomeActive()

        XCTAssertEqual(system.session.launchState, .workspaceReady)
        XCTAssertEqual(system.session.openDocument?.text, "# Entry\n\nAutosaved text.")
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertNil(system.session.workspaceAlertError)
        XCTAssertFalse(system.viewModel.isShowingConflictResolution)
    }

    @MainActor
    func testLiveObservationReloadsCleanEditorAfterOutsideWrite() async throws {
        let fixture = try makeLiveDocumentFixture(
            named: "Observed.md",
            contents: "# Entry\n\nOriginal text."
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let liveManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await liveManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let system = makeEditorSystem(
            documentManager: liveManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        try "# Entry\n\nUpdated from Mac.".write(to: fixture.fileURL, atomically: true, encoding: .utf8)
        try await waitUntil {
            system.session.openDocument?.text == "# Entry\n\nUpdated from Mac."
        }

        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
        XCTAssertFalse(system.viewModel.isShowingConflictResolution)
    }

    @MainActor
    func testLiveObservationPreservesDirtyBufferDuringOutsideWrite() async throws {
        let fixture = try makeLiveDocumentFixture(
            named: "DirtyObserved.md",
            contents: "# Entry\n\nOriginal text."
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let liveManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await liveManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let system = makeEditorSystem(
            documentManager: liveManager,
            initialDocument: initialDocument,
            autosaveDelay: .seconds(5)
        )

        system.viewModel.handleTextChange("# Entry\n\nLocal buffer wins.")
        try "# Entry\n\nUpdated from Mac.".write(to: fixture.fileURL, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(system.session.openDocument?.text, "# Entry\n\nLocal buffer wins.")
        XCTAssertTrue(system.session.openDocument?.isDirty ?? false)
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertFalse(system.viewModel.isShowingConflictResolution)
    }

    @MainActor
    func testEmptyFileCanOpenEditAndSaveNormally() async throws {
        let fixture = try makeLiveDocumentFixture(
            named: "Empty.md",
            contents: ""
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let liveManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await liveManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let system = makeEditorSystem(
            documentManager: liveManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        XCTAssertEqual(system.session.openDocument?.text, "")
        XCTAssertTrue(system.viewModel.showsEmptyDocumentPlaceholder)

        system.viewModel.handleTextChange("# Empty\n\nNow it has content.")
        try await waitUntil {
            system.session.openDocument?.isDirty == false
                && system.session.openDocument?.text == "# Empty\n\nNow it has content."
        }

        XCTAssertFalse(system.viewModel.showsEmptyDocumentPlaceholder)
        XCTAssertNil(system.viewModel.documentLocationText)
        XCTAssertEqual(
            try String(contentsOf: fixture.fileURL, encoding: .utf8),
            "# Empty\n\nNow it has content."
        )
    }

    @MainActor
    func testReasonablyLargeMarkdownFileCanOpenAndSaveWithoutStateChurn() async throws {
        let largeBody = Array(repeating: "- bullet item for markdown workspace regression coverage", count: 4_000)
            .joined(separator: "\n")
        let fixture = try makeLiveDocumentFixture(
            named: "Large.md",
            contents: "# Large\n\n\(largeBody)\n"
        )
        defer { removeItemIfPresent(at: fixture.workspaceURL) }

        let liveManager = LiveDocumentManager(securityScopedAccess: TestDocumentSecurityAccessHandler())
        let initialDocument = try await liveManager.openDocument(
            at: fixture.fileURL,
            in: fixture.workspaceURL
        )
        let system = makeEditorSystem(
            documentManager: liveManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        let revisedText = initialDocument.text + "\n## Tail\n\nExtra line."
        system.viewModel.handleTextChange(revisedText)
        try await waitUntil {
            system.session.openDocument?.isDirty == false
                && system.session.openDocument?.text == revisedText
        }

        XCTAssertFalse(system.viewModel.showsSaveStatusIndicator)
        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)
        XCTAssertEqual(try String(contentsOf: fixture.fileURL, encoding: .utf8), revisedText)
    }

    @MainActor
    func testSaveAcknowledgementMergesConfirmedVersionWithoutClobberingNewerEdits() async throws {
        let initialDocument = makeVersionedDocument(versionIndex: 0, text: PreviewSampleData.cleanDocument.text)
        let documentManager = VersionTrackingDocumentManager(
            initialDocument: initialDocument,
            saveDelay: .milliseconds(120)
        )
        let system = makeEditorSystem(
            documentManager: documentManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("First revision")
        try await Task.sleep(for: .milliseconds(40))
        system.viewModel.handleTextChange("Second revision")

        try await Task.sleep(for: .milliseconds(140))

        XCTAssertEqual(system.session.openDocument?.text, "Second revision")
        XCTAssertEqual(system.session.openDocument?.loadedVersion.contentDigest, "version-1")
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertTrue(system.session.openDocument?.isDirty ?? false)
        XCTAssertEqual(system.session.openDocument?.saveState, .saving)

        try await Task.sleep(for: .milliseconds(180))

        let saveInputs = await documentManager.saveInputs

        XCTAssertEqual(saveInputs.map(\.text), ["First revision", "Second revision"])
        XCTAssertEqual(saveInputs.map(\.loadedVersion.contentDigest), ["version-0", "version-1"])
        XCTAssertEqual(system.session.openDocument?.text, "Second revision")
        XCTAssertEqual(system.session.openDocument?.loadedVersion.contentDigest, "version-2")
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    func testAutosaveDebounceOnlySavesLatestSnapshot() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(10))
        let system = makeEditorSystem(documentManager: documentManager)

        system.viewModel.handleTextChange("First draft")
        try await Task.sleep(for: .milliseconds(20))
        system.viewModel.handleTextChange("Second draft")
        try await Task.sleep(for: .milliseconds(140))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Second draft"])
        XCTAssertEqual(system.session.openDocument?.text, "Second draft")
        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)
    }

    @MainActor
    func testCanceledSupersededAutosaveDoesNotFireAtOriginalDeadline() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(5))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(80)
        )

        system.viewModel.handleTextChange("First draft")
        try await Task.sleep(for: .milliseconds(20))
        system.viewModel.handleTextChange("Second draft")

        try await Task.sleep(for: .milliseconds(70))

        let savedTexts = await documentManager.savedTexts

        XCTAssertTrue(
            savedTexts.isEmpty,
            "The canceled autosave must not request a save when its original delay expires."
        )
        XCTAssertEqual(system.session.openDocument?.text, "Second draft")
        XCTAssertTrue(system.session.openDocument?.isDirty ?? false)
    }

    @MainActor
    func testReplacingAutosaveTaskOnlySavesLatestSnapshot() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(5))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(80)
        )

        system.viewModel.handleTextChange("First draft")
        try await Task.sleep(for: .milliseconds(20))
        system.viewModel.handleTextChange("Second draft")

        try await Task.sleep(for: .milliseconds(140))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Second draft"])
        XCTAssertEqual(system.session.openDocument?.text, "Second draft")
        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)
    }

    @MainActor
    func testSaveOrderingRemainsSerializedWhenEditArrivesDuringSave() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(120))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("First revision")
        try await Task.sleep(for: .milliseconds(40))
        system.viewModel.handleTextChange("Second revision")
        try await Task.sleep(for: .milliseconds(320))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["First revision", "Second revision"])
        XCTAssertEqual(system.session.openDocument?.text, "Second revision")
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    func testRedDotTransitionsFromUnsavedToSavingToSaved() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(90))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(20)
        )

        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)

        system.viewModel.handleTextChange("Edited text")
        XCTAssertTrue(system.viewModel.showsUnsavedIndicator)
        XCTAssertFalse(system.viewModel.showsSaveStatusIndicator)
        XCTAssertEqual(system.session.openDocument?.saveState, .unsaved)

        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(system.session.openDocument?.saveState, .saving)
        XCTAssertTrue(system.viewModel.showsUnsavedIndicator)
        XCTAssertFalse(system.viewModel.showsSaveStatusIndicator)

        try await Task.sleep(for: .milliseconds(120))
        guard case .saved = system.session.openDocument?.saveState else {
            return XCTFail("Expected save state to become saved after autosave succeeds.")
        }
        XCTAssertFalse(system.viewModel.showsUnsavedIndicator)
    }

    @MainActor
    func testSaveFailureKeepsRedDotVisible() async throws {
        let documentManager = RecordingDocumentManager(
            saveDelay: .milliseconds(20),
            failureSequence: [
                AppError.documentSaveFailed(name: "Inbox.md", details: "Disk write failed.")
            ]
        )
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("Broken save")
        try await Task.sleep(for: .milliseconds(80))

        guard case .failed = system.session.openDocument?.saveState else {
            return XCTFail("Expected save state to become failed when autosave throws.")
        }
        XCTAssertTrue(system.session.openDocument?.isDirty ?? false)
        XCTAssertTrue(system.viewModel.showsUnsavedIndicator)
        XCTAssertTrue(system.viewModel.showsSaveStatusIndicator)
    }

    @MainActor
    func testSaveFailureChromeAndPathStayScopedToActiveDocument() async throws {
        var nestedDocument = PreviewSampleData.failedSaveDocument
        nestedDocument.saveState = .failed(PreviewSampleData.saveFailedError)
        nestedDocument.isDirty = true

        let system = makeEditorSystem(
            documentManager: RecordingDocumentManager(saveDelay: .milliseconds(10)),
            initialDocument: nestedDocument,
            autosaveDelay: .milliseconds(20)
        )
        system.session.path = [.editor(nestedDocument.url)]

        XCTAssertTrue(system.viewModel.showsSaveStatusIndicator)
        XCTAssertEqual(system.viewModel.title, nestedDocument.displayName)
        XCTAssertEqual(system.viewModel.documentLocationText, "Journal/2026")

        system.session.path = [.editor(PreviewSampleData.cleanDocument.url)]

        XCTAssertNil(system.viewModel.currentRouteDocument)
        XCTAssertFalse(system.viewModel.showsSaveStatusIndicator)
        XCTAssertEqual(system.viewModel.title, PreviewSampleData.cleanDocument.displayName)
        XCTAssertNil(system.viewModel.documentLocationText)
    }

    @MainActor
    func testDisappearFlushesPendingDirtyDocumentImmediately() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(10))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .seconds(5)
        )

        system.viewModel.handleTextChange("Disappear flush")
        system.viewModel.handleDisappear(for: PreviewSampleData.cleanDocument.url)
        try await Task.sleep(for: .milliseconds(40))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Disappear flush"])
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    func testBackgroundTransitionFlushesPendingDirtyDocumentImmediately() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(10))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .seconds(5)
        )

        system.viewModel.handleTextChange("Background flush")
        system.viewModel.handleScenePhaseChange(.background)
        try await Task.sleep(for: .milliseconds(40))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Background flush"])
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    func testBackgroundFlushCancelDoesNotAllowDuplicateAutosaveAfterOriginalDelay() async throws {
        let documentManager = RecordingDocumentManager(saveDelay: .milliseconds(10))
        let system = makeEditorSystem(
            documentManager: documentManager,
            autosaveDelay: .milliseconds(120)
        )

        system.viewModel.handleTextChange("Background flush")
        system.viewModel.handleScenePhaseChange(.background)
        try await Task.sleep(for: .milliseconds(220))

        let savedTexts = await documentManager.savedTexts

        XCTAssertEqual(savedTexts, ["Background flush"])
        XCTAssertFalse(system.session.openDocument?.isDirty ?? true)
    }

    @MainActor
    func testForegroundRevalidationDoesNotConflictAfterMergedSaveAcknowledgement() async throws {
        let initialDocument = makeVersionedDocument(versionIndex: 0, text: PreviewSampleData.cleanDocument.text)
        let documentManager = VersionTrackingDocumentManager(
            initialDocument: initialDocument,
            saveDelay: .milliseconds(120)
        )
        let system = makeEditorSystem(
            documentManager: documentManager,
            initialDocument: initialDocument,
            autosaveDelay: .milliseconds(20)
        )

        system.viewModel.handleTextChange("First revision")
        try await Task.sleep(for: .milliseconds(40))
        system.viewModel.handleTextChange("Second revision")
        try await Task.sleep(for: .milliseconds(340))

        await system.coordinator.handleSceneDidBecomeActive()

        XCTAssertEqual(system.session.launchState, .workspaceReady)
        XCTAssertEqual(system.session.openDocument?.text, "Second revision")
        XCTAssertEqual(system.session.openDocument?.loadedVersion.contentDigest, "version-2")
        XCTAssertEqual(system.session.openDocument?.conflictState, DocumentConflictState.none)
        XCTAssertNil(system.session.workspaceAlertError)
    }

    @MainActor
    private func makeEditorSystem(
        documentManager: any DocumentManager,
        initialDocument: OpenDocument = PreviewSampleData.cleanDocument,
        workspaceSnapshot: WorkspaceSnapshot? = nil,
        autosaveDelay: Duration = .milliseconds(40)
    ) -> (session: AppSession, coordinator: AppCoordinator, viewModel: EditorViewModel) {
        let snapshot = workspaceSnapshot ?? makeWorkspaceSnapshot(containing: initialDocument)
        let session = AppSession()
        session.launchState = .workspaceReady
        session.workspaceSnapshot = snapshot
        session.openDocument = initialDocument
        session.path = [.editor(initialDocument.url)]

        let logger = DebugLogger()
        let coordinator = AppCoordinator(
            session: session,
            workspaceManager: StubWorkspaceManager(
                bookmarkStore: StubBookmarkStore(),
                readySnapshot: snapshot
            ),
            documentManager: documentManager,
            errorReporter: DefaultErrorReporter(logger: logger),
            folderPickerBridge: StubFolderPickerBridge(),
            logger: logger
        )

        let viewModel = EditorViewModel(
            session: session,
            coordinator: coordinator,
            editorAppearanceStore: EditorAppearanceStore(),
            autosaveDelay: autosaveDelay
        )
        viewModel.handleAppear(for: initialDocument.url)

        return (session, coordinator, viewModel)
    }

    @MainActor
    private func makeWorkspaceSnapshot(containing document: OpenDocument) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: document.workspaceRootURL,
            displayName: document.workspaceRootURL.lastPathComponent,
            rootNodes: [
                .file(
                    .init(
                        url: document.url,
                        displayName: document.displayName,
                        subtitle: nil
                    )
                ),
            ],
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    private func makeVersionedDocument(versionIndex: Int, text: String) -> OpenDocument {
        var document = PreviewSampleData.cleanDocument
        document.text = text
        document.loadedVersion = DocumentVersion(
            contentModificationDate: Date(timeIntervalSince1970: TimeInterval(1_710_000_000 + versionIndex)),
            fileSize: text.utf8.count,
            contentDigest: "version-\(versionIndex)"
        )
        document.isDirty = false
        document.saveState = .idle
        document.conflictState = .none
        return document
    }

    private func makeLiveDocumentFixture(
        named name: String,
        contents: String
    ) throws -> (workspaceURL: URL, fileURL: URL) {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appending(path: "EditorAutosaveTests")
            .appending(path: UUID().uuidString)
            .appending(path: "Workspace")
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fileURL = workspaceURL.appending(path: name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return (workspaceURL, fileURL)
    }

    private func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }

            try await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for condition.")
    }
}

private actor RecordingDocumentManager: DocumentManager {
    let saveDelay: Duration
    private var failureSequence: [AppError]
    private var conflictSequence: [OpenDocument]
    private(set) var savedTexts: [String] = []

    init(
        saveDelay: Duration,
        failureSequence: [AppError] = [],
        conflictSequence: [OpenDocument] = []
    ) {
        self.saveDelay = saveDelay
        self.failureSequence = failureSequence
        self.conflictSequence = conflictSequence
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        throw AppError.documentUnavailable(name: url.lastPathComponent)
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        try? await Task.sleep(for: saveDelay)
        savedTexts.append(document.text)

        if failureSequence.isEmpty == false {
            throw failureSequence.removeFirst()
        }

        if overwriteConflict == false, conflictSequence.isEmpty == false {
            return conflictSequence.removeFirst()
        }

        var savedDocument = document
        savedDocument.isDirty = false
        savedDocument.saveState = .saved(Date(timeIntervalSince1970: 1_710_000_100))
        savedDocument.conflictState = .none
        return savedDocument
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}
}

private actor VersionTrackingDocumentManager: DocumentManager {
    let saveDelay: Duration

    private let workspaceRootURL: URL
    private let fileURL: URL
    private let displayName: String
    private var diskText: String
    private var diskVersion: DocumentVersion
    private var nextVersionIndex: Int

    private(set) var saveInputs: [OpenDocument] = []

    init(initialDocument: OpenDocument, saveDelay: Duration) {
        self.saveDelay = saveDelay
        workspaceRootURL = initialDocument.workspaceRootURL
        fileURL = initialDocument.url
        displayName = initialDocument.displayName
        diskText = initialDocument.text
        diskVersion = initialDocument.loadedVersion
        nextVersionIndex = 1
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        makeDocument(
            text: diskText,
            loadedVersion: diskVersion,
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        makeDocument(
            text: diskText,
            loadedVersion: diskVersion,
            isDirty: false,
            saveState: .idle,
            conflictState: .none
        )
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        guard document.loadedVersion.matchesCurrentDisk(diskVersion) else {
            return LiveDocumentManager.makeConflictDocument(
                from: document,
                kind: .modifiedOnDisk
            )
        }

        return document
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        try? await Task.sleep(for: saveDelay)
        saveInputs.append(document)

        guard overwriteConflict || document.loadedVersion.matchesCurrentDisk(diskVersion) else {
            return LiveDocumentManager.makeConflictDocument(
                from: document,
                kind: .modifiedOnDisk
            )
        }

        let savedVersion = makeVersion(index: nextVersionIndex, text: document.text)
        nextVersionIndex += 1
        diskText = document.text
        diskVersion = savedVersion

        return makeDocument(
            text: document.text,
            loadedVersion: savedVersion,
            isDirty: false,
            saveState: .saved(Date(timeIntervalSince1970: TimeInterval(1_710_000_100 + nextVersionIndex))),
            conflictState: .none
        )
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {}

    private func makeDocument(
        text: String,
        loadedVersion: DocumentVersion,
        isDirty: Bool,
        saveState: DocumentSaveState,
        conflictState: DocumentConflictState
    ) -> OpenDocument {
        OpenDocument(
            url: fileURL,
            workspaceRootURL: workspaceRootURL,
            relativePath: "Inbox.md",
            displayName: displayName,
            text: text,
            loadedVersion: loadedVersion,
            isDirty: isDirty,
            saveState: saveState,
            conflictState: conflictState
        )
    }

    private func makeVersion(index: Int, text: String) -> DocumentVersion {
        DocumentVersion(
            contentModificationDate: Date(timeIntervalSince1970: TimeInterval(1_710_000_000 + index)),
            fileSize: text.utf8.count,
            contentDigest: "version-\(index)"
        )
    }
}

private actor DelayedLiveDocumentManager: DocumentManager {
    private let base: any DocumentManager
    private let saveDelay: Duration

    init(base: any DocumentManager, saveDelay: Duration) {
        self.base = base
        self.saveDelay = saveDelay
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        try await base.openDocument(at: url, in: workspaceRootURL)
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        try await base.reloadDocument(from: document)
    }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        try await base.revalidateDocument(document)
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        try? await Task.sleep(for: saveDelay)
        return try await base.saveDocument(document, overwriteConflict: overwriteConflict)
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        try await base.observeDocumentChanges(for: document)
    }

    func relocateDocumentSession(
        for document: OpenDocument,
        to url: URL,
        relativePath: String
    ) async {
        await base.relocateDocumentSession(
            for: document,
            to: url,
            relativePath: relativePath
        )
    }
}

private struct TestDocumentSecurityAccessHandler: SecurityScopedAccessHandling {
    func makeBookmark(for url: URL) throws -> Data {
        Data()
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(url: URL(fileURLWithPath: "/tmp"), displayName: "tmp", isStale: false)
    }

    func validateAccess(to url: URL) throws {}

    func beginAccess(to url: URL) throws -> SecurityScopedAccessLease {
        SecurityScopedAccessLease(url: url, stopHandler: nil)
    }

    func withAccess<Value>(to url: URL, operation: (URL) throws -> Value) throws -> Value {
        try operation(url)
    }

    func withAccess<Value>(
        toDescendantAt relativePath: String,
        within workspaceRootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
        let descendantURL = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(workspaceRootURL) { partialURL, component in
                partialURL.appending(path: String(component))
            }
        return try operation(descendantURL)
    }
}
