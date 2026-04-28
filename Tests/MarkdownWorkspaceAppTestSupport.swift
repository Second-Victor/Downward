import Foundation
import XCTest
@testable import Downward

class MarkdownWorkspaceAppTestCase: XCTestCase {
    @MainActor
    func makeWorkspaceSnapshotReplacingRootFile(
        oldURL: URL,
        with replacement: WorkspaceNode
    ) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes.map { node in
                node.url == oldURL ? replacement : node
            },
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    func makeWorkspaceSnapshotReplacingFile(
        oldURL: URL,
        with replacement: WorkspaceNode
    ) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: replacingNode(oldURL: oldURL, with: replacement, in: PreviewSampleData.nestedWorkspace.rootNodes),
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    func makeWorkspaceSnapshotRenamingJournalFolder(to folderName: String) -> WorkspaceSnapshot {
        let renamedFolderURL = PreviewSampleData.workspaceRootURL.appending(path: folderName)
        let renamedYearURL = renamedFolderURL.appending(path: "2026")

        return makeWorkspaceSnapshotReplacingFile(
            oldURL: PreviewSampleData.journalURL,
            with: .folder(
                .init(
                    url: renamedFolderURL,
                    displayName: folderName,
                    children: [
                        .folder(
                            .init(
                                url: renamedYearURL,
                                displayName: "2026",
                                children: [
                                    .file(
                                        .init(
                                            url: renamedYearURL.appending(path: "2026-04-13.md"),
                                            displayName: "2026-04-13.md",
                                            subtitle: "Daily note"
                                        )
                                    ),
                                    .file(
                                        .init(
                                            url: renamedYearURL.appending(path: "Ideas.markdown"),
                                            displayName: "Ideas.markdown",
                                            subtitle: "Scratchpad"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                )
            )
        )
    }

    @MainActor
    func makeWorkspaceSnapshotRemovingRootFile(url: URL) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes.filter { $0.url != url },
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    func makeWorkspaceSnapshotRemovingFile(url: URL) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: removingNode(url: url, in: PreviewSampleData.nestedWorkspace.rootNodes),
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    func makeWorkspaceSnapshotAppendingRootFile(_ node: WorkspaceNode) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: PreviewSampleData.nestedWorkspace.rootURL,
            displayName: PreviewSampleData.nestedWorkspace.displayName,
            rootNodes: PreviewSampleData.nestedWorkspace.rootNodes + [node],
            lastUpdated: PreviewSampleData.previewDate
        )
    }

    @MainActor
    func replacingNode(
        oldURL: URL,
        with replacement: WorkspaceNode,
        in nodes: [WorkspaceNode]
    ) -> [WorkspaceNode] {
        nodes.map { node in
            if node.url == oldURL {
                return replacement
            }

            guard case let .folder(folder) = node else {
                return node
            }

            return .folder(
                .init(
                    url: folder.url,
                    displayName: folder.displayName,
                    children: replacingNode(oldURL: oldURL, with: replacement, in: folder.children)
                )
            )
        }
    }

    @MainActor
    func removingNode(
        url: URL,
        in nodes: [WorkspaceNode]
    ) -> [WorkspaceNode] {
        nodes.compactMap { node in
            if node.url == url {
                return nil
            }

            guard case let .folder(folder) = node else {
                return node
            }

            return .folder(
                .init(
                    url: folder.url,
                    displayName: folder.displayName,
                    children: removingNode(url: url, in: folder.children)
                )
            )
        }
    }

    func waitUntil(
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

    func makeTemporaryWorkspace(named name: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownWorkspaceAppSmokeTests")
            .appending(path: UUID().uuidString)
            .appending(path: name)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    func createFile(
        named name: String,
        contents: String,
        in parentURL: URL
    ) throws -> URL {
        let fileURL = parentURL.appending(path: name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func makePreviewReadmeDocument() -> OpenDocument {
        OpenDocument(
            url: PreviewSampleData.readmeDocumentURL,
            workspaceRootURL: PreviewSampleData.workspaceRootURL,
            relativePath: "References/README.md",
            displayName: "README.md",
            text: """
            # README

            Snapshot-backed open.
            """,
            loadedVersion: PreviewSampleData.cleanDocument.loadedVersion,
            isDirty: false,
            saveState: .saved(PreviewSampleData.previewDate),
            conflictState: .none
        )
    }

    func trustedEditorPath(for document: OpenDocument) -> [AppRoute] {
        [.trustedEditor(document.url, document.relativePath)]
    }
}

struct SmokeTestSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    func makeBookmark(for url: URL) throws -> Data { Data() }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        ResolvedSecurityScopedURL(url: URL(filePath: "/tmp"), displayName: "tmp", isStale: false)
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
        try operation(
            relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .reduce(workspaceRootURL) { partialURL, component in
                    partialURL.appending(path: String(component))
                }
        )
    }
}

struct FailingSmokeWorkspaceEnumerator: WorkspaceEnumerating {
    let error: AppError

    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        throw error
    }
}

struct RestoringSmokeSecurityScopedAccessHandler: SecurityScopedAccessHandling {
    let resolvedBookmarks: [Data: ResolvedSecurityScopedURL]

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSecurityScopedURL {
        resolvedBookmarks[data] ?? ResolvedSecurityScopedURL(
            url: URL(filePath: "/tmp"),
            displayName: "tmp",
            isStale: false
        )
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
        guard let url = WorkspaceRelativePath.resolveCandidate(relativePath, within: workspaceRootURL) else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
        }

        return try operation(url)
    }
}

actor FailingDocumentManager: DocumentManager {
    let openError: AppError

    init(openError: AppError) {
        self.openError = openError
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument { throw openError }
    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument { throw openError }
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument { throw openError }
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument { throw openError }
    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> { throw openError }
    func relocateDocumentSession(for document: OpenDocument, to url: URL, relativePath: String) async {}
}

actor RestorationDocumentManager: DocumentManager {
    let openedDocument: OpenDocument
    let revalidatedDocument: OpenDocument?

    init(openedDocument: OpenDocument, revalidatedDocument: OpenDocument? = nil) {
        self.openedDocument = openedDocument
        self.revalidatedDocument = revalidatedDocument
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument { openedDocument }
    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument { openedDocument }
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument { revalidatedDocument ?? document }
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument { document }
    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }
    func relocateDocumentSession(for document: OpenDocument, to url: URL, relativePath: String) async {}
}

actor MutationTrackingDocumentManager: DocumentManager {
    private(set) var savedInputs: [OpenDocument] = []
    private(set) var relocatedInputs: [RelocatedDocumentSession] = []

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        throw AppError.documentUnavailable(name: url.lastPathComponent)
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument { document }
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument { document }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument {
        savedInputs.append(document)
        var savedDocument = document
        savedDocument.isDirty = false
        savedDocument.saveState = .saved(Date(timeIntervalSince1970: 1_710_000_000))
        savedDocument.conflictState = .none
        return savedDocument
    }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }

    func relocateDocumentSession(for document: OpenDocument, to url: URL, relativePath: String) async {
        relocatedInputs.append(
            RelocatedDocumentSession(
                fromRelativePath: document.relativePath,
                toURL: url,
                toRelativePath: relativePath
            )
        )
    }
}

actor DelayedOpenDocumentManager: DocumentManager {
    let documents: [URL: OpenDocument]
    let openDelays: [URL: Duration]
    private(set) var observedURLs: [URL] = []

    init(documents: [URL: OpenDocument], openDelays: [URL: Duration]) {
        self.documents = documents
        self.openDelays = openDelays
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        if let delay = openDelays[url] {
            try await Task.sleep(for: delay)
        }
        guard let document = documents[url] else {
            throw AppError.documentUnavailable(name: url.lastPathComponent)
        }
        return document
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument { document }
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument { document }
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument { document }

    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        observedURLs.append(document.url)
        return AsyncStream { continuation in continuation.finish() }
    }

    func relocateDocumentSession(for document: OpenDocument, to url: URL, relativePath: String) async {}
}

actor DelayedRevalidationDocumentManager: DocumentManager {
    let revalidatedDocument: OpenDocument
    let revalidationDelay: Duration

    init(revalidatedDocument: OpenDocument, revalidationDelay: Duration) {
        self.revalidatedDocument = revalidatedDocument
        self.revalidationDelay = revalidationDelay
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument { revalidatedDocument }
    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument { document }

    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        try await Task.sleep(for: revalidationDelay)
        return revalidatedDocument
    }

    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument { document }
    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }
    func relocateDocumentSession(for document: OpenDocument, to url: URL, relativePath: String) async {}
}

actor RelativePathOnlyDocumentManager: DocumentManager {
    let documentsByRelativePath: [String: OpenDocument]
    private(set) var openedRelativePaths: [String] = []
    private(set) var attemptedURLBasedOpenURLs: [URL] = []

    init(documentsByRelativePath: [String: OpenDocument]) {
        self.documentsByRelativePath = documentsByRelativePath
    }

    func openDocument(at url: URL, in workspaceRootURL: URL) async throws -> OpenDocument {
        attemptedURLBasedOpenURLs.append(url)
        throw AppError.documentUnavailable(name: url.lastPathComponent)
    }

    func openDocument(atRelativePath relativePath: String, in workspaceRootURL: URL) async throws -> OpenDocument {
        openedRelativePaths.append(relativePath)
        guard let document = documentsByRelativePath[relativePath] else {
            throw AppError.documentUnavailable(
                name: relativePath.split(separator: "/").last.map(String.init) ?? "Document"
            )
        }
        return document
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument { document }
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument { document }
    func saveDocument(_ document: OpenDocument, overwriteConflict: Bool) async throws -> OpenDocument { document }
    func observeDocumentChanges(for document: OpenDocument) async throws -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }
    func relocateDocumentSession(for document: OpenDocument, to url: URL, relativePath: String) async {}
    func recordedOpenedRelativePaths() -> [String] { openedRelativePaths }
    func recordedURLBasedOpenAttempts() -> [URL] { attemptedURLBasedOpenURLs }
}

struct RelocatedDocumentSession: Equatable, Sendable {
    let fromRelativePath: String
    let toURL: URL
    let toRelativePath: String
}

enum SequencedWorkspaceRefreshResponse: Sendable {
    case success(snapshot: WorkspaceSnapshot, delay: Duration)
    case failure(error: AppError, delay: Duration)
}

struct SequencedWorkspaceMutationResponse: Sendable {
    let result: WorkspaceMutationResult
    let delay: Duration
}

actor SequencedRefreshWorkspaceManager: WorkspaceManager {
    private var refreshResponses: [SequencedWorkspaceRefreshResponse]
    private let fallbackSnapshot: WorkspaceSnapshot
    private let createResponse: SequencedWorkspaceMutationResponse?
    private let createFolderResponse: SequencedWorkspaceMutationResponse?
    private let renameResponse: SequencedWorkspaceMutationResponse?
    private let deleteResponse: SequencedWorkspaceMutationResponse?
    private var createdFileInitialContents: [WorkspaceCreatedFileInitialContent] = []

    init(
        refreshResponses: [SequencedWorkspaceRefreshResponse],
        fallbackSnapshot: WorkspaceSnapshot,
        createResponse: SequencedWorkspaceMutationResponse? = nil,
        createFolderResponse: SequencedWorkspaceMutationResponse? = nil,
        renameResponse: SequencedWorkspaceMutationResponse? = nil,
        deleteResponse: SequencedWorkspaceMutationResponse? = nil
    ) {
        self.refreshResponses = refreshResponses
        self.fallbackSnapshot = fallbackSnapshot
        self.createResponse = createResponse
        self.createFolderResponse = createFolderResponse
        self.renameResponse = renameResponse
        self.deleteResponse = deleteResponse
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult { .ready(fallbackSnapshot) }
    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult { .ready(fallbackSnapshot) }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        let response = refreshResponses.isEmpty == false
            ? refreshResponses.removeFirst()
            : .success(snapshot: fallbackSnapshot, delay: .zero)

        switch response {
        case let .success(snapshot, delay):
            try await Task.sleep(for: delay)
            return snapshot
        case let .failure(error, delay):
            try await Task.sleep(for: delay)
            throw error
        }
    }

    func createFile(
        named proposedName: String,
        in folderURL: URL?,
        initialContent: WorkspaceCreatedFileInitialContent
    ) async throws -> WorkspaceMutationResult {
        createdFileInitialContents.append(initialContent)
        if let createResponse {
            try await Task.sleep(for: createResponse.delay)
            return createResponse.result
        }
        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .createdFile(
                url: (folderURL ?? fallbackSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func recordedCreatedFileInitialContents() -> [WorkspaceCreatedFileInitialContent] {
        createdFileInitialContents
    }

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        if let createFolderResponse {
            try await Task.sleep(for: createFolderResponse.delay)
            return createFolderResponse.result
        }
        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .createdFolder(
                url: (folderURL ?? fallbackSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        if let renameResponse {
            try await Task.sleep(for: renameResponse.delay)
            return renameResponse.result
        }
        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: url.deletingLastPathComponent().appending(path: proposedName),
                displayName: proposedName,
                relativePath: proposedName
            )
        )
    }

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        let destinationFolderURL = destinationFolderURL ?? fallbackSnapshot.rootURL
        let destinationURL = destinationFolderURL.appending(path: url.lastPathComponent)
        let relativePath = WorkspaceRelativePath.make(for: destinationURL, within: fallbackSnapshot.rootURL)
            ?? destinationURL.lastPathComponent

        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .renamedFile(
                oldURL: url,
                newURL: destinationURL,
                displayName: destinationURL.lastPathComponent,
                relativePath: relativePath
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        if let deleteResponse {
            try await Task.sleep(for: deleteResponse.delay)
            return deleteResponse.result
        }
        return WorkspaceMutationResult(
            snapshot: fallbackSnapshot,
            outcome: .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {}
}

actor MutationTestingWorkspaceManager: WorkspaceManager {
    let refreshSnapshot: WorkspaceSnapshot
    let selectResult: WorkspaceRestoreResult?
    let renameOutcome: WorkspaceMutationOutcome?
    let deleteOutcome: WorkspaceMutationOutcome?
    let clearError: AppError?
    let refreshError: AppError?
    private(set) var deleteCalls: [URL] = []

    init(
        refreshSnapshot: WorkspaceSnapshot,
        selectResult: WorkspaceRestoreResult? = nil,
        renameOutcome: WorkspaceMutationOutcome? = nil,
        deleteOutcome: WorkspaceMutationOutcome? = nil,
        clearError: AppError? = nil,
        refreshError: AppError? = nil
    ) {
        self.refreshSnapshot = refreshSnapshot
        self.selectResult = selectResult
        self.renameOutcome = renameOutcome
        self.deleteOutcome = deleteOutcome
        self.clearError = clearError
        self.refreshError = refreshError
    }

    func restoreWorkspace() async -> WorkspaceRestoreResult { .ready(refreshSnapshot) }

    func selectWorkspace(at url: URL) async -> WorkspaceRestoreResult {
        if let selectResult { return selectResult }
        return .ready(refreshSnapshot)
    }

    func refreshCurrentWorkspace() async throws -> WorkspaceSnapshot {
        if let refreshError { throw refreshError }
        return refreshSnapshot
    }

    func createFile(
        named proposedName: String,
        in folderURL: URL?,
        initialContent: WorkspaceCreatedFileInitialContent
    ) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .createdFile(
                url: (folderURL ?? refreshSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func createFolder(named proposedName: String, in folderURL: URL?) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: .createdFolder(
                url: (folderURL ?? refreshSnapshot.rootURL).appending(path: proposedName),
                displayName: proposedName
            )
        )
    }

    func renameFile(at url: URL, to proposedName: String) async throws -> WorkspaceMutationResult {
        WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: renameOutcome ?? .renamedFile(
                oldURL: url,
                newURL: url.deletingLastPathComponent().appending(path: proposedName),
                displayName: proposedName,
                relativePath: proposedName
            )
        )
    }

    func moveItem(at url: URL, toFolder destinationFolderURL: URL?) async throws -> WorkspaceMutationResult {
        let destinationFolderURL = destinationFolderURL ?? refreshSnapshot.rootURL
        let destinationURL = destinationFolderURL.appending(path: url.lastPathComponent)
        let relativePath = WorkspaceRelativePath.make(for: destinationURL, within: refreshSnapshot.rootURL)
            ?? destinationURL.lastPathComponent

        return WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: renameOutcome ?? .renamedFile(
                oldURL: url,
                newURL: destinationURL,
                displayName: destinationURL.lastPathComponent,
                relativePath: relativePath
            )
        )
    }

    func deleteFile(at url: URL) async throws -> WorkspaceMutationResult {
        deleteCalls.append(url)
        return WorkspaceMutationResult(
            snapshot: refreshSnapshot,
            outcome: deleteOutcome ?? .deletedFile(url: url, displayName: url.lastPathComponent)
        )
    }

    func clearWorkspaceSelection() async throws {
        if let clearError { throw clearError }
    }
}
