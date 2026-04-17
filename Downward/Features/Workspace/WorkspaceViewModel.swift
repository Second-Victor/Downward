import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class WorkspaceViewModel {
    let session: AppSession
    var searchQuery = "" {
        didSet {
            refreshSearchResultsIfNeeded()
        }
    }
    var isLoading = false
    var isRefreshing = false
    var isPerformingFileOperation = false
    var loadError: UserFacingError?
    var isShowingCreateFilePrompt = false
    var createFileName = "Untitled.md"
    var isShowingRenamePrompt = false
    var renameFileName = ""
    var isShowingDeleteConfirmation = false
    var isShowingRecentFiles = false
    private(set) var expandedFolderRelativePaths: Set<String> = []

    private(set) var pendingRenameFile: WorkspaceNode.File?
    private(set) var pendingDeleteFile: WorkspaceNode.File?
    private(set) var searchResults: [WorkspaceSearchResult] = []

    private let coordinator: AppCoordinator
    private let recentFilesStore: RecentFilesStore
    private let searcher: any WorkspaceSearching
    private var loadTask: Task<Void, Never>?
    private var fileOperationTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var fileOperationGeneration = 0
    private var hasLoadedInitialSnapshot = false
    private var pendingCreateFolderURL: URL?
    private var lastSearchContext: SearchComputationContext?

    init(
        session: AppSession,
        coordinator: AppCoordinator,
        recentFilesStore: RecentFilesStore,
        searcher: any WorkspaceSearching = LiveWorkspaceSearcher()
    ) {
        self.session = session
        self.coordinator = coordinator
        self.recentFilesStore = recentFilesStore
        self.searcher = searcher
        observeSearchSnapshotChanges()
    }

    var workspaceTitle: String {
        session.workspaceSnapshot?.displayName ?? "Workspace"
    }

    var nodes: [WorkspaceNode] {
        session.workspaceSnapshot?.rootNodes ?? []
    }

    var recentFiles: [RecentFileItem] {
        recentFilesStore.recentItems(for: session.workspaceSnapshot)
    }

    var isEmpty: Bool {
        isLoading == false && loadError == nil && nodes.isEmpty
    }

    var isSearching: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var isShowingErrorState: Bool {
        loadError != nil && session.workspaceSnapshot == nil
    }

    var isBusy: Bool {
        isRefreshing || isPerformingFileOperation
    }

    var pendingRenameTitle: String {
        pendingRenameFile?.displayName ?? "Rename File"
    }

    var pendingDeleteTitle: String {
        pendingDeleteFile?.displayName ?? "Delete File"
    }

    var currentWorkspaceRootURL: URL {
        session.workspaceSnapshot?.rootURL ?? URL(filePath: "/")
    }

    var searchQueryDescription: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var searchResultsSummaryText: String {
        let resultCount = searchResults.count
        return resultCount == 1 ? "1 matching file" : "\(resultCount) matching files"
    }

    func loadSnapshotIfNeeded() {
        guard hasLoadedInitialSnapshot == false else {
            syncExpandedFoldersToCurrentSnapshot()
            refreshSearchResultsIfNeeded()
            return
        }

        hasLoadedInitialSnapshot = true

        guard session.workspaceSnapshot == nil else {
            syncExpandedFoldersToCurrentSnapshot()
            refreshSearchResultsIfNeeded()
            return
        }

        startSnapshotLoad()
    }

    func refresh() {
        startSnapshotLoad()
    }

    func refreshFromPullToRefresh() async {
        guard let context = beginSnapshotLoad() else {
            return
        }

        await performSnapshotLoad(generation: context.generation, hadSnapshot: context.hadSnapshot)
    }

    func showSettings() {
        coordinator.presentSettings()
    }

    func presentRecentFiles() {
        isShowingRecentFiles = true
    }

    func dismissRecentFiles() {
        isShowingRecentFiles = false
    }

    func openRecentFile(_ item: RecentFileItem) {
        isShowingRecentFiles = false
        let preferredURL = session.workspaceSnapshot?.fileURL(forRelativePath: item.relativePath)
            ?? item.url(in: currentWorkspaceRootURL)
        openDocument(relativePath: item.relativePath, preferredURL: preferredURL)
    }

    func toggleFolderExpansion(atRelativePath relativePath: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedFolderRelativePaths.contains(relativePath) {
                expandedFolderRelativePaths.remove(relativePath)
            } else {
                expandedFolderRelativePaths.insert(relativePath)
            }
        }
    }

    func toggleFolderExpansion(at url: URL) {
        guard let relativePath = folderRelativePath(for: url) else {
            return
        }

        toggleFolderExpansion(atRelativePath: relativePath)
    }

    /// Browser/search/recent-file opens should come through trusted relative identity when the
    /// caller already knows it. The preferred URL stays secondary route/display metadata only.
    func openDocument(
        relativePath: String,
        preferredURL: URL? = nil
    ) {
        coordinator.presentEditor(
            relativePath: relativePath,
            preferredURL: preferredURL
        )
    }

    /// Raw URL opens are a compatibility lane for callers that do not already have trusted
    /// workspace-relative identity. Browser/search tree code should not use this path.
    func openDocument(_ url: URL) {
        if let relativePath = relativePath(forFile: url) {
            openDocument(relativePath: relativePath, preferredURL: url)
        } else {
            coordinator.presentEditor(for: url)
        }
    }

    func openSearchResult(_ result: WorkspaceSearchResult) {
        openDocument(relativePath: result.relativePath, preferredURL: result.url)
    }

    func isFolderExpanded(atRelativePath relativePath: String) -> Bool {
        return expandedFolderRelativePaths.contains(relativePath)
    }

    func isFolderExpanded(at url: URL) -> Bool {
        guard let relativePath = folderRelativePath(for: url) else {
            return false
        }

        return isFolderExpanded(atRelativePath: relativePath)
    }

    func expandFolderAndAncestors(at url: URL) {
        guard let relativePath = folderRelativePath(for: url) else {
            return
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.isEmpty == false else {
            return
        }

        for index in 0..<components.count {
            expandedFolderRelativePaths.insert(
                components.prefix(index + 1).joined(separator: "/")
            )
        }
    }

    func syncExpandedFoldersToCurrentSnapshot() {
        let validFolderPaths = folderRelativePaths(in: nodes)
        expandedFolderRelativePaths.formIntersection(validFolderPaths)
    }

    func presentCreateFile(in folderURL: URL?) {
        pendingCreateFolderURL = folderURL
        createFileName = suggestedCreateFileName(in: folderURL)
        isShowingCreateFilePrompt = true
    }

    func cancelCreateFile() {
        isShowingCreateFilePrompt = false
        createFileName = "Untitled.md"
        pendingCreateFolderURL = nil
    }

    func createFile() {
        let pendingFolderURL = pendingCreateFolderURL
        let proposedName = createFileName
        cancelCreateFile()

        startFileOperation { [self] in
            _ = await self.coordinator.createFile(
                named: proposedName,
                in: pendingFolderURL
            )
        }
    }

    func presentRename(for file: WorkspaceNode.File) {
        pendingRenameFile = file
        renameFileName = file.displayName
        isShowingRenamePrompt = true
    }

    func cancelRename() {
        isShowingRenamePrompt = false
        renameFileName = ""
        pendingRenameFile = nil
    }

    func renameFile() {
        guard let pendingRenameFile else {
            return
        }

        let proposedName = renameFileName
        cancelRename()

        startFileOperation { [self] in
            _ = await self.coordinator.renameFile(
                at: pendingRenameFile.url,
                to: proposedName
            )
        }
    }

    func presentDelete(for file: WorkspaceNode.File) {
        pendingDeleteFile = file
        isShowingDeleteConfirmation = true
    }

    func cancelDelete() {
        isShowingDeleteConfirmation = false
        pendingDeleteFile = nil
    }

    func deleteFile() {
        guard let pendingDeleteFile else {
            return
        }

        cancelDelete()

        startFileOperation { [self] in
            _ = await self.coordinator.deleteFile(at: pendingDeleteFile.url)
        }
    }

    func nodes(in folderURL: URL?) -> [WorkspaceNode] {
        guard let folderURL else {
            return nodes
        }

        return folderNode(for: folderURL)?.children ?? []
    }

    func refreshSearchResultsIfNeeded() {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            normalizedQuery.isEmpty == false,
            let snapshot = session.workspaceSnapshot
        else {
            lastSearchContext = nil
            if searchResults.isEmpty == false {
                searchResults = []
            }
            return
        }

        let context = SearchComputationContext(
            snapshot: snapshot,
            query: normalizedQuery
        )
        guard context != lastSearchContext else {
            return
        }

        searchResults = searcher.results(in: snapshot, matching: normalizedQuery)
        lastSearchContext = context
    }

    private func startSnapshotLoad() {
        guard let context = beginSnapshotLoad() else {
            return
        }

        loadTask = Task { [self] in
            await performSnapshotLoad(generation: context.generation, hadSnapshot: context.hadSnapshot)
        }
    }

    private func beginSnapshotLoad() -> (generation: Int, hadSnapshot: Bool)? {
        guard session.launchState == .workspaceReady else {
            return nil
        }

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let hadSnapshot = session.workspaceSnapshot != nil
        if hadSnapshot {
            isRefreshing = true
        } else {
            isLoading = true
            loadError = nil
        }

        return (generation, hadSnapshot)
    }

    private func performSnapshotLoad(generation: Int, hadSnapshot: Bool) async {
        defer {
            finishSnapshotLoadIfCurrent(generation)
        }

        let result = await coordinator.refreshWorkspace()
        guard Task.isCancelled == false else {
            return
        }

        guard generation == loadGeneration else {
            return
        }

        guard let result else {
            return
        }

        switch result {
        case .success:
            loadError = nil
            syncExpandedFoldersToCurrentSnapshot()
            refreshSearchResultsIfNeeded()
        case let .failure(error):
            if hadSnapshot {
                if session.launchState == .workspaceReady {
                    session.workspaceAlertError = error
                }
            } else {
                loadError = error
            }
        }
    }

    private func startFileOperation(_ operation: @escaping @MainActor () async -> Void) {
        guard isPerformingFileOperation == false else {
            return
        }

        fileOperationTask?.cancel()
        fileOperationGeneration += 1
        let generation = fileOperationGeneration
        isPerformingFileOperation = true
        fileOperationTask = Task {
            defer {
                finishFileOperationIfCurrent(generation)
            }

            await operation()
            guard Task.isCancelled == false else {
                return
            }

            syncExpandedFoldersToCurrentSnapshot()
            refreshSearchResultsIfNeeded()
        }
    }

    private func finishSnapshotLoadIfCurrent(_ generation: Int) {
        guard generation == loadGeneration else {
            return
        }

        isLoading = false
        isRefreshing = false
        loadTask = nil
    }

    private func finishFileOperationIfCurrent(_ generation: Int) {
        guard generation == fileOperationGeneration else {
            return
        }

        isPerformingFileOperation = false
        fileOperationTask = nil
    }

    private func suggestedCreateFileName(in folderURL: URL?) -> String {
        let existingNames = Set<String>(
            nodes(in: folderURL)
                .compactMap { node in
                    guard node.isFile else {
                        return nil
                    }

                    return node.displayName.lowercased()
                }
        )
        let baseName = "Untitled"
        var candidateName = "\(baseName).md"
        var duplicateIndex = 2

        while existingNames.contains(candidateName.lowercased()) {
            candidateName = "\(baseName) \(duplicateIndex).md"
            duplicateIndex += 1
        }

        return candidateName
    }

    private func folderNode(for folderURL: URL) -> WorkspaceNode.Folder? {
        findFolder(at: folderURL, within: nodes)
    }

    private func folderRelativePath(for url: URL) -> String? {
        session.workspaceSnapshot?.relativePath(for: url)
    }

    private func relativePath(forFile url: URL) -> String? {
        if let openDocument = session.openDocument, openDocument.url == url {
            return openDocument.relativePath
        }

        return session.workspaceSnapshot?.relativePath(for: url)
    }

    private func folderRelativePaths(
        in nodes: [WorkspaceNode],
        parentRelativePath: String? = nil
    ) -> Set<String> {
        var relativePaths = Set<String>()

        for node in nodes {
            guard case let .folder(folder) = node else {
                continue
            }

            let currentPath = joinedRelativePath(
                parentRelativePath,
                component: folder.url.lastPathComponent
            )
            relativePaths.insert(currentPath)

            relativePaths.formUnion(
                folderRelativePaths(
                    in: folder.children,
                    parentRelativePath: currentPath
                )
            )
        }

        return relativePaths
    }

    private func joinedRelativePath(_ parentRelativePath: String?, component: String) -> String {
        guard let parentRelativePath, parentRelativePath.isEmpty == false else {
            return component
        }

        return "\(parentRelativePath)/\(component)"
    }

    private func findFolder(at folderURL: URL, within nodes: [WorkspaceNode]) -> WorkspaceNode.Folder? {
        for node in nodes {
            guard case let .folder(folder) = node else {
                continue
            }

            if folder.url == folderURL {
                return folder
            }

            if let descendant = findFolder(at: folderURL, within: folder.children) {
                return descendant
            }
        }

        return nil
    }

    private func observeSearchSnapshotChanges() {
        withObservationTracking {
            _ = session.workspaceSnapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshSearchResultsIfNeeded()
                self?.observeSearchSnapshotChanges()
            }
        }
    }
}

private struct SearchComputationContext: Equatable {
    let snapshot: WorkspaceSnapshot
    let query: String
}
