import SwiftUI

struct WorkspaceFolderScreen: View {
    let viewModel: WorkspaceViewModel
    let showsSettingsButton: Bool
    let navigationMode: WorkspaceNavigationMode
    let expandedFolderURL: URL?

    var body: some View {
        Group {
            if viewModel.isSearching {
                WorkspaceSearchResultsView(
                    viewModel: viewModel,
                    navigationMode: navigationMode
                )
            } else if viewModel.nodes.isEmpty {
                refreshableStateView(
                    title: "No Supported Files",
                    systemImage: "doc.text.magnifyingglass",
                    message: "This workspace does not contain any supported files yet."
                )
            } else {
                List {
                    Section {
                        WorkspaceTreeRows(
                            viewModel: viewModel,
                            nodes: viewModel.nodes,
                            depth: 0,
                            navigationMode: navigationMode
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.refreshFromPullToRefresh()
                }
            }
        }
        .task(id: expandedFolderURL) {
            viewModel.syncExpandedFoldersToCurrentSnapshot()
            if let expandedFolderURL {
                viewModel.expandFolderAndAncestors(at: expandedFolderURL)
            }
        }
        .navigationTitle(viewModel.workspaceTitle)
        .searchable(text: searchQueryBinding, prompt: "Search Files")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("New File", systemImage: "plus") {
                    viewModel.presentCreateFile(in: nil)
                }
                .disabled(viewModel.isBusy)
                .accessibilityLabel("New Text File")
                .accessibilityHint("Creates a Markdown or text file in the workspace root.")

                if showsSettingsButton {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Recent Files", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                            viewModel.presentRecentFiles()
                        }
                        .accessibilityHint("Shows recently opened files for this workspace.")

                        Button("Settings", systemImage: "gearshape") {
                            viewModel.showSettings()
                        }
                        .accessibilityHint("Shows workspace management options.")
                    }
                    .disabled(viewModel.isBusy)
                }
            }
        }
        .sheet(isPresented: recentFilesSheetBinding) {
            NavigationStack {
                RecentFilesSheet(viewModel: viewModel)
            }
        }
        .alert("New Text File", isPresented: createPromptBinding) {
            TextField("File Name", text: createFileNameBinding)

            Button("Create") {
                viewModel.createFile()
            }
            .disabled(viewModel.createFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {
                viewModel.cancelCreateFile()
            }
        } message: {
            Text("Create a new Markdown or text file.")
        }
        .alert("Rename File", isPresented: renamePromptBinding) {
            TextField("File Name", text: renameFileNameBinding)

            Button("Rename") {
                viewModel.renameFile()
            }
            .disabled(viewModel.renameFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {
                viewModel.cancelRename()
            }
        } message: {
            Text("Rename \(viewModel.pendingRenameTitle).")
        }
        .confirmationDialog(
            "Delete File",
            isPresented: deletePromptBinding,
            titleVisibility: .visible
        ) {
            Button("Delete \(viewModel.pendingDeleteTitle)", role: .destructive) {
                viewModel.deleteFile()
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text("This removes the file from the workspace.")
        }
    }

    private var createPromptBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingCreateFilePrompt },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelCreateFile()
                }
            }
        )
    }

    private var createFileNameBinding: Binding<String> {
        Binding(
            get: { viewModel.createFileName },
            set: { viewModel.createFileName = $0 }
        )
    }

    private var renamePromptBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingRenamePrompt },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelRename()
                }
            }
        )
    }

    private var renameFileNameBinding: Binding<String> {
        Binding(
            get: { viewModel.renameFileName },
            set: { viewModel.renameFileName = $0 }
        )
    }

    private var deletePromptBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingDeleteConfirmation },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelDelete()
                }
            }
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.searchQuery = $0 }
        )
    }

    private var recentFilesSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingRecentFiles },
            set: { isPresented in
                if isPresented == false {
                    viewModel.dismissRecentFiles()
                }
            }
        )
    }

    private func refreshableStateView(title: String, systemImage: String, message: String) -> some View {
        ScrollView {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(message)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        }
        .refreshable {
            await viewModel.refreshFromPullToRefresh()
        }
    }
}

private struct WorkspaceTreeRows: View {
    let viewModel: WorkspaceViewModel
    let nodes: [WorkspaceNode]
    let depth: Int
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        ForEach(nodes) { node in
            WorkspaceTreeRow(
                                viewModel: viewModel,
                                node: node,
                                depth: depth,
                                navigationMode: navigationMode
                            )
            if
                case let .folder(folder) = node,
                viewModel.isFolderExpanded(at: folder.url)
            {
                WorkspaceTreeRows(
                    viewModel: viewModel,
                    nodes: folder.children,
                    depth: depth + 1,
                    navigationMode: navigationMode
                )
            }
        }
    }
}

private struct WorkspaceTreeRow: View {
    let viewModel: WorkspaceViewModel
    let node: WorkspaceNode
    let depth: Int
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        switch node {
        case let .folder(folder):
            Button {
                viewModel.toggleFolderExpansion(at: folder.url)
            } label: {
                WorkspaceRowView(
                    node: node,
                    isSelected: false,
                    hierarchyDepth: depth,
                    folderDisclosureState: viewModel.isFolderExpanded(at: folder.url) ? .expanded : .collapsed
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("New File", systemImage: "plus") {
                    viewModel.presentCreateFile(in: folder.url)
                }
                .accessibilityLabel("New File in \(node.displayName)")
                .accessibilityHint("Creates a Markdown or text file inside this folder.")
            }
        case .file:
            fileRow
        }
    }

    @ViewBuilder
    private var fileRow: some View {
        if navigationMode.usesValueNavigationLinks == false {
            Button {
                viewModel.openDocument(node.url)
            } label: {
                WorkspaceRowView(
                    node: node,
                    isSelected: viewModel.isSelected(node),
                    hierarchyDepth: depth
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                fileContextMenu
            }
            .swipeActions {
                fileSwipeActions
            }
        } else {
            NavigationLink(value: AppRoute.editor(node.url)) {
                WorkspaceRowView(
                    node: node,
                    isSelected: viewModel.isSelected(node),
                    hierarchyDepth: depth
                )
            }
            .contextMenu {
                fileContextMenu
            }
            .swipeActions {
                fileSwipeActions
            }
        }
    }

    @ViewBuilder
    private var fileContextMenu: some View {
        Button("Rename", systemImage: "pencil") {
            if case let .file(file) = node {
                viewModel.presentRename(for: file)
            }
        }
        .accessibilityLabel("Rename \(node.displayName)")
        .accessibilityHint("Changes the file name.")

        Button("Delete", systemImage: "trash", role: .destructive) {
            if case let .file(file) = node {
                viewModel.presentDelete(for: file)
            }
        }
        .accessibilityLabel("Delete \(node.displayName)")
        .accessibilityHint("Deletes this file from the workspace.")
    }

    @ViewBuilder
    private var fileSwipeActions: some View {
        Button("Rename", systemImage: "pencil") {
            if case let .file(file) = node {
                viewModel.presentRename(for: file)
            }
        }
        .tint(.accentColor)

        Button("Delete", systemImage: "trash", role: .destructive) {
            if case let .file(file) = node {
                viewModel.presentDelete(for: file)
            }
        }
    }
}

#Preview("Large Type Root") {
    NavigationStack {
        WorkspaceFolderScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.largeWorkspace.displayName),
                    snapshot: PreviewSampleData.largeWorkspace
                )
                container.workspaceViewModel.expandFolderAndAncestors(at: PreviewSampleData.largeWorkspace.rootNodes[0].url)
                return container.workspaceViewModel
            }(),
            showsSettingsButton: true,
            navigationMode: .stackPath,
            expandedFolderURL: nil
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Nested Folder") {
    NavigationStack {
        WorkspaceFolderScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.deepWorkspace.displayName),
                    snapshot: PreviewSampleData.deepWorkspace
                )
                container.workspaceViewModel.expandFolderAndAncestors(at: PreviewSampleData.deepWorkspaceRootFolderURL)
                return container.workspaceViewModel
            }(),
            showsSettingsButton: false,
            navigationMode: .stackPath,
            expandedFolderURL: nil
        )
    }
}

#Preview("Large Folder") {
    NavigationStack {
        WorkspaceFolderScreen(
            viewModel: {
                let container = AppContainer.preview(
                    launchState: .workspaceReady,
                    accessState: .ready(displayName: PreviewSampleData.largeWorkspace.displayName),
                    snapshot: PreviewSampleData.largeWorkspace
                )
                container.workspaceViewModel.expandFolderAndAncestors(at: PreviewSampleData.largeWorkspace.rootNodes[0].url)
                return container.workspaceViewModel
            }(),
            showsSettingsButton: true,
            navigationMode: .stackPath,
            expandedFolderURL: nil
        )
    }
}
