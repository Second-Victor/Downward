import Foundation
import Observation
import SwiftUI

enum WorkspaceCreateItemKind: Equatable {
    case file
    case folder

    var promptTitle: String {
        switch self {
        case .file:
            "New Text File"
        case .folder:
            "New Folder"
        }
    }

    var fieldTitle: String {
        switch self {
        case .file:
            "File Name"
        case .folder:
            "Folder Name"
        }
    }

    var promptMessage: String {
        switch self {
        case .file:
            "Create a new Markdown or text file."
        case .folder:
            "Create a new folder in the workspace."
        }
    }

    var createActionTitle: String {
        switch self {
        case .file:
            "Create File"
        case .folder:
            "Create Folder"
        }
    }

    var defaultName: String {
        switch self {
        case .file:
            "Untitled.md"
        case .folder:
            "Untitled Folder"
        }
    }
}

struct WorkspaceMoveDestination: Identifiable, Equatable {
    let relativePath: String?
    let title: String
    let subtitle: String?

    var id: String {
        relativePath ?? "__workspace_root__"
    }
}

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
    var isShowingCreatePrompt = false
    var createItemName = WorkspaceCreateItemKind.file.defaultName
    var isShowingRenamePrompt = false
    var renameItemName = ""
    var isShowingDeleteConfirmation = false
    var isShowingMoveSheet = false
    var isShowingRecentFiles = false
    private(set) var expandedFolderRelativePaths: Set<String> = []
    private(set) var pendingCreateItemKind: WorkspaceCreateItemKind = .file

    private(set) var pendingRenameNode: WorkspaceNode?
    private(set) var pendingDeleteNode: WorkspaceNode?
    private(set) var pendingMoveNode: WorkspaceNode?
    private(set) var searchResults: [WorkspaceSearchResult] = []

    private let coordinator: AppCoordinator
    private let recentFilesStore: RecentFilesStore
    private let searcher: any WorkspaceSearching
    private var loadTask: Task<Void, Never>?
    private var fileOperationTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var fileOperationGeneration = 0
    private var hasLoadedInitialSnapshot = false
    private var pendingCreateParentFolderURL: URL?
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

    var areRowActionsDisabled: Bool {
        isBusy
    }

    var pendingRenameTitle: String {
        pendingRenameNode?.displayName ?? "Rename Item"
    }

    var pendingDeleteTitle: String {
        pendingDeleteNode?.displayName ?? "Delete Item"
    }

    var pendingMoveTitle: String {
        pendingMoveNode?.displayName ?? "Move Item"
    }

    var renamePromptTitle: String {
        pendingRenameNode?.isFolder == true ? "Rename Folder" : "Rename File"
    }

    var renamePromptFieldTitle: String {
        pendingRenameNode?.isFolder == true ? "Folder Name" : "File Name"
    }

    var deletePromptTitle: String {
        pendingDeleteNode?.isFolder == true ? "Delete Folder" : "Delete File"
    }

    var deletePromptMessage: String {
        pendingDeleteNode?.isFolder == true
            ? "This removes the folder and its contents from the workspace."
            : "This removes the file from the workspace."
    }

    var moveSheetTitle: String {
        pendingMoveNode?.isFolder == true ? "Move Folder" : "Move File"
    }

    var moveDestinations: [WorkspaceMoveDestination] {
        guard let pendingMoveNode else {
            return []
        }

        return availableMoveDestinations(for: pendingMoveNode)
    }

    var createPromptTitle: String {
        pendingCreateItemKind.promptTitle
    }

    var createPromptFieldTitle: String {
        pendingCreateItemKind.fieldTitle
    }

    var createPromptMessage: String {
        pendingCreateItemKind.promptMessage
    }

    var createPromptActionTitle: String {
        pendingCreateItemKind.createActionTitle
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
        guard let snapshot = session.workspaceSnapshot else {
            return
        }

        isShowingRecentFiles = false
        coordinator.presentEditor(
            relativePath: item.relativePath,
            preferredURL: item.preferredRouteURL(in: snapshot),
            source: .recentFile
        )
    }

    func removeRecentFiles(at offsets: IndexSet) {
        guard let snapshot = session.workspaceSnapshot else {
            return
        }

        let itemsToRemove = offsets.compactMap { index in
            recentFiles.indices.contains(index) ? recentFiles[index] : nil
        }

        for item in itemsToRemove {
            recentFilesStore.removeItem(using: snapshot, relativePath: item.relativePath)
        }
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

    private func rewriteExpandedFolderRelativePaths(
        from oldPrefix: String,
        to newPrefix: String
    ) {
        guard expandedFolderRelativePaths.isEmpty == false, oldPrefix != newPrefix else {
            return
        }

        expandedFolderRelativePaths = Set(
            expandedFolderRelativePaths.map { path in
                rewrittenExpandedFolderRelativePath(
                    path,
                    from: oldPrefix,
                    to: newPrefix
                )
            }
        )
    }

    func presentCreateFile(in folderURL: URL?) {
        presentCreateItem(.file, in: folderURL)
    }

    func presentCreateFolder(in folderURL: URL?) {
        presentCreateItem(.folder, in: folderURL)
    }

    func cancelCreateItem() {
        isShowingCreatePrompt = false
        createItemName = WorkspaceCreateItemKind.file.defaultName
        pendingCreateItemKind = .file
        pendingCreateParentFolderURL = nil
    }

    func createItem() {
        let pendingFolderURL = pendingCreateParentFolderURL
        let proposedName = createItemName
        let itemKind = pendingCreateItemKind
        cancelCreateItem()

        startFileOperation { [self] in
            let result: Result<WorkspaceMutationOutcome, UserFacingError>
            switch itemKind {
            case .file:
                result = await self.coordinator.createFile(
                    named: proposedName,
                    in: pendingFolderURL
                )
            case .folder:
                result = await self.coordinator.createFolder(
                    named: proposedName,
                    in: pendingFolderURL
                )
            }

            guard case let .success(outcome) = result else {
                return
            }

            revealCreatedItem(using: outcome)
        }
    }

    func presentRename(for node: WorkspaceNode) {
        pendingRenameNode = node
        renameItemName = node.displayName
        isShowingRenamePrompt = true
    }

    func cancelRename() {
        isShowingRenamePrompt = false
        renameItemName = ""
        pendingRenameNode = nil
    }

    func renameItem() {
        guard let pendingRenameNode else {
            return
        }

        let proposedName = renameItemName
        let renamedNode = pendingRenameNode
        let oldExpandedRelativePath = renamedNode.isFolder ? folderRelativePath(for: renamedNode.url) : nil
        cancelRename()

        startFileOperation { [self] in
            let result = await self.coordinator.renameFile(
                at: renamedNode.url,
                to: proposedName
            )

            guard case let .success(outcome) = result else {
                return
            }

            guard case let .renamedFolder(_, _, _, newRelativePath) = outcome,
                  let oldExpandedRelativePath else {
                return
            }

            rewriteExpandedFolderRelativePaths(
                from: oldExpandedRelativePath,
                to: newRelativePath
            )
        }
    }

    func presentDelete(for node: WorkspaceNode) {
        pendingDeleteNode = node
        isShowingDeleteConfirmation = true
    }

    func cancelDelete() {
        isShowingDeleteConfirmation = false
        pendingDeleteNode = nil
    }

    func deleteItem() {
        guard let pendingDeleteNode else {
            return
        }

        cancelDelete()

        startFileOperation { [self] in
            _ = await self.coordinator.deleteFile(at: pendingDeleteNode.url)
        }
    }

    func presentMove(for node: WorkspaceNode) {
        let destinations = availableMoveDestinations(for: node)
        guard destinations.isEmpty == false else {
            session.workspaceAlertError = UserFacingError(
                title: node.isFolder ? "Move Folder" : "Move File",
                message: "No other destination folder is available in this workspace.",
                recoverySuggestion: "Create another folder or choose a different item."
            )
            return
        }

        pendingMoveNode = node
        isShowingMoveSheet = true
    }

    func cancelMove() {
        isShowingMoveSheet = false
        pendingMoveNode = nil
    }

    func moveItem(toFolderRelativePath destinationFolderRelativePath: String?) {
        guard let pendingMoveNode else {
            return
        }

        let nodeToMove = pendingMoveNode
        let oldExpandedRelativePath = nodeToMove.isFolder ? folderRelativePath(for: nodeToMove.url) : nil
        guard
            destinationFolderRelativePath == nil
                || folderURL(forRelativePath: destinationFolderRelativePath) != nil
        else {
            return
        }
        let destinationFolderURL = resolvedMoveDestinationFolderURL(
            forRelativePath: destinationFolderRelativePath
        )
        cancelMove()

        performMove(
            nodeToMove,
            toFolderURL: destinationFolderURL,
            oldExpandedRelativePath: oldExpandedRelativePath
        )
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
            session.workspaceAlertError = UserFacingError(
                title: "Operation in Progress",
                message: "Finish the current workspace change before starting another one.",
                recoverySuggestion: "Wait for the current action to complete, then try again."
            )
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

    private func presentCreateItem(_ itemKind: WorkspaceCreateItemKind, in folderURL: URL?) {
        pendingCreateItemKind = itemKind
        pendingCreateParentFolderURL = folderURL
        createItemName = suggestedCreateItemName(itemKind, in: folderURL)
        isShowingCreatePrompt = true
    }

    private func revealCreatedItem(using outcome: WorkspaceMutationOutcome) {
        let createdURL: URL
        switch outcome {
        case let .createdFile(url, _), let .createdFolder(url, _):
            createdURL = url
        default:
            return
        }

        let parentURL = createdURL.deletingLastPathComponent()
        expandFolderAndAncestors(at: parentURL)
    }

    private func performMove(
        _ node: WorkspaceNode,
        toFolderURL destinationFolderURL: URL?,
        oldExpandedRelativePath: String?
    ) {
        startFileOperation { [self] in
            let result = await self.coordinator.moveItem(
                at: node.url,
                toFolder: destinationFolderURL
            )

            guard case let .success(outcome) = result else {
                return
            }

            applyPostMoveState(
                for: outcome,
                oldExpandedRelativePath: oldExpandedRelativePath
            )
        }
    }

    private func applyPostMoveState(
        for outcome: WorkspaceMutationOutcome,
        oldExpandedRelativePath: String?
    ) {
        let oldParentURL: URL
        let newParentURL: URL

        switch outcome {
        case let .renamedFile(oldURL, newURL, _, _):
            oldParentURL = oldURL.deletingLastPathComponent()
            newParentURL = newURL.deletingLastPathComponent()
        case let .renamedFolder(oldURL, newURL, _, newRelativePath):
            oldParentURL = oldURL.deletingLastPathComponent()
            newParentURL = newURL.deletingLastPathComponent()

            if let oldExpandedRelativePath {
                rewriteExpandedFolderRelativePaths(
                    from: oldExpandedRelativePath,
                    to: newRelativePath
                )
            }
        default:
            return
        }

        if WorkspaceIdentity.normalizedPath(for: oldParentURL) != WorkspaceIdentity.normalizedPath(for: newParentURL) {
            expandFolderAndAncestors(at: newParentURL)
        }
    }

    private func suggestedCreateItemName(
        _ itemKind: WorkspaceCreateItemKind,
        in folderURL: URL?
    ) -> String {
        switch itemKind {
        case .file:
            suggestedCreateFileName(in: folderURL)
        case .folder:
            suggestedCreateFolderName(in: folderURL)
        }
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

    private func suggestedCreateFolderName(in folderURL: URL?) -> String {
        let existingNames = Set<String>(
            nodes(in: folderURL)
                .compactMap { node in
                    guard node.isFolder else {
                        return nil
                    }

                    return node.displayName.lowercased()
                }
        )
        let baseName = "Untitled Folder"
        var candidateName = baseName
        var duplicateIndex = 2

        while existingNames.contains(candidateName.lowercased()) {
            candidateName = "\(baseName) \(duplicateIndex)"
            duplicateIndex += 1
        }

        return candidateName
    }

    private func availableMoveDestinations(for node: WorkspaceNode) -> [WorkspaceMoveDestination] {
        guard let sourceRelativePath = relativePath(for: node.url) else {
            return []
        }

        let currentParentRelativePath = parentRelativePath(for: sourceRelativePath)
        var destinations: [WorkspaceMoveDestination] = []

        if currentParentRelativePath != nil {
            destinations.append(
                WorkspaceMoveDestination(
                    relativePath: nil,
                    title: workspaceTitle,
                    subtitle: "Workspace Root"
                )
            )
        }

        destinations.append(
            contentsOf: folderMoveDestinations(
                in: nodes,
                parentRelativePath: nil,
                sourceRelativePath: sourceRelativePath,
                currentParentRelativePath: currentParentRelativePath,
                movingFolder: node.isFolder
            )
        )

        return destinations
    }

    private func folderNode(for folderURL: URL) -> WorkspaceNode.Folder? {
        findFolder(at: folderURL, within: nodes)
    }

    private func folderURL(forRelativePath relativePath: String?) -> URL? {
        guard let relativePath else {
            return nil
        }

        return findFolder(relativePath: relativePath, within: nodes, parentRelativePath: nil)?.url
    }

    private func resolvedMoveDestinationFolderURL(forRelativePath relativePath: String?) -> URL? {
        if let relativePath {
            return folderURL(forRelativePath: relativePath)
        }

        return session.workspaceSnapshot?.rootURL
    }

    private func folderRelativePath(for url: URL) -> String? {
        session.workspaceSnapshot?.relativePath(for: url)
    }

    private func relativePath(for url: URL) -> String? {
        session.workspaceSnapshot?.relativePath(for: url)
    }

    private func relativePath(forFile url: URL) -> String? {
        if let openDocument = session.openDocument, openDocument.url == url {
            return openDocument.relativePath
        }

        return session.workspaceSnapshot?.relativePath(for: url)
    }

    private func parentRelativePath(for relativePath: String) -> String? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else {
            return nil
        }

        return components.dropLast().joined(separator: "/")
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

    private func rewrittenExpandedFolderRelativePath(
        _ path: String,
        from oldPrefix: String,
        to newPrefix: String
    ) -> String {
        guard path == oldPrefix || path.hasPrefix("\(oldPrefix)/") else {
            return path
        }

        if path == oldPrefix {
            return newPrefix
        }

        let suffix = path.dropFirst(oldPrefix.count + 1)
        return "\(newPrefix)/\(suffix)"
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

    private func findFolder(
        relativePath: String,
        within nodes: [WorkspaceNode],
        parentRelativePath: String?
    ) -> WorkspaceNode.Folder? {
        for node in nodes {
            guard case let .folder(folder) = node else {
                continue
            }

            let currentPath = joinedRelativePath(
                parentRelativePath,
                component: folder.url.lastPathComponent
            )
            if currentPath == relativePath {
                return folder
            }

            if let descendant = findFolder(
                relativePath: relativePath,
                within: folder.children,
                parentRelativePath: currentPath
            ) {
                return descendant
            }
        }

        return nil
    }

    private func folderMoveDestinations(
        in nodes: [WorkspaceNode],
        parentRelativePath: String?,
        sourceRelativePath: String,
        currentParentRelativePath: String?,
        movingFolder: Bool
    ) -> [WorkspaceMoveDestination] {
        var destinations: [WorkspaceMoveDestination] = []

        for node in nodes {
            guard case let .folder(folder) = node else {
                continue
            }

            let currentPath = joinedRelativePath(
                parentRelativePath,
                component: folder.url.lastPathComponent
            )
            let isSourceFolder = movingFolder && currentPath == sourceRelativePath
            let isDescendantOfSource = movingFolder && currentPath.hasPrefix("\(sourceRelativePath)/")
            let isCurrentParent = currentPath == currentParentRelativePath

            if isSourceFolder == false, isDescendantOfSource == false, isCurrentParent == false {
                destinations.append(
                    WorkspaceMoveDestination(
                        relativePath: currentPath,
                        title: folder.displayName,
                        subtitle: currentPath
                    )
                )
            }

            destinations.append(
                contentsOf: folderMoveDestinations(
                    in: folder.children,
                    parentRelativePath: currentPath,
                    sourceRelativePath: sourceRelativePath,
                    currentParentRelativePath: currentParentRelativePath,
                    movingFolder: movingFolder
                )
            )
        }

        return destinations
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
