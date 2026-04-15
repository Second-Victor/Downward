import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceViewModel {
    let session: AppSession
    var isLoading = false
    var isRefreshing = false
    var isPerformingFileOperation = false
    var loadError: UserFacingError?
    var isShowingCreateFilePrompt = false
    var createFileName = "Untitled.md"
    var isShowingRenamePrompt = false
    var renameFileName = ""
    var isShowingDeleteConfirmation = false

    private(set) var pendingRenameFile: WorkspaceNode.File?
    private(set) var pendingDeleteFile: WorkspaceNode.File?

    private let coordinator: AppCoordinator
    private var loadTask: Task<Void, Never>?
    private var fileOperationTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var hasLoadedInitialSnapshot = false
    private var pendingCreateFolderURL: URL?

    init(session: AppSession, coordinator: AppCoordinator) {
        self.session = session
        self.coordinator = coordinator
    }

    var workspaceTitle: String {
        session.workspaceSnapshot?.displayName ?? "Workspace"
    }

    var nodes: [WorkspaceNode] {
        session.workspaceSnapshot?.rootNodes ?? []
    }

    var isEmpty: Bool {
        isLoading == false && loadError == nil && nodes.isEmpty
    }

    var isShowingErrorState: Bool {
        loadError != nil && session.workspaceSnapshot == nil
    }

    var isBusy: Bool {
        isRefreshing || isPerformingFileOperation
    }

    var selectedDocumentURL: URL? {
        session.path.last?.editorURL
    }

    var pendingRenameTitle: String {
        pendingRenameFile?.displayName ?? "Rename File"
    }

    var pendingDeleteTitle: String {
        pendingDeleteFile?.displayName ?? "Delete File"
    }

    func loadSnapshotIfNeeded() {
        guard hasLoadedInitialSnapshot == false else {
            return
        }

        hasLoadedInitialSnapshot = true

        guard session.workspaceSnapshot == nil else {
            return
        }

        startSnapshotLoad()
    }

    func refresh() {
        startSnapshotLoad()
    }

    func showSettings() {
        coordinator.presentSettings()
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

    func isSelected(_ node: WorkspaceNode) -> Bool {
        node.url == selectedDocumentURL
    }

    func title(for folderURL: URL?) -> String {
        guard let folderURL else {
            return workspaceTitle
        }

        return folderNode(for: folderURL)?.displayName ?? folderURL.lastPathComponent
    }

    func nodes(in folderURL: URL?) -> [WorkspaceNode] {
        guard let folderURL else {
            return nodes
        }

        return folderNode(for: folderURL)?.children ?? []
    }

    func isFolderMissing(_ folderURL: URL) -> Bool {
        folderNode(for: folderURL) == nil
    }

    private func startSnapshotLoad() {
        guard session.launchState == .workspaceReady else {
            return
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

        loadTask = Task {
            let result = await coordinator.refreshWorkspace()
            guard Task.isCancelled == false else {
                return
            }

            guard generation == loadGeneration else {
                return
            }

            isLoading = false
            isRefreshing = false

            guard let result else {
                return
            }

            switch result {
            case .success:
                loadError = nil
            case let .failure(error):
                if hadSnapshot {
                    session.lastError = error
                } else {
                    loadError = error
                }
            }
        }
    }

    private func startFileOperation(_ operation: @escaping @MainActor () async -> Void) {
        guard isPerformingFileOperation == false else {
            return
        }

        fileOperationTask?.cancel()
        isPerformingFileOperation = true
        fileOperationTask = Task {
            await operation()
            guard Task.isCancelled == false else {
                return
            }

            isPerformingFileOperation = false
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

    private func folderNode(for folderURL: URL) -> WorkspaceNode.Folder? {
        findFolder(at: folderURL, within: nodes)
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
}
