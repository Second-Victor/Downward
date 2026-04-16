import SwiftUI

struct WorkspaceFolderScreen: View {
    let viewModel: WorkspaceViewModel
    let folderURL: URL?
    let showsSettingsButton: Bool
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        Group {
            if viewModel.isSearching {
                WorkspaceSearchResultsView(
                    viewModel: viewModel,
                    navigationMode: navigationMode
                )
            } else if let folderURL, viewModel.isFolderMissing(folderURL) {
                refreshableStateView(
                    title: "Folder Unavailable",
                    systemImage: "folder.badge.questionmark",
                    message: "This folder is no longer visible in the current workspace snapshot."
                )
            } else if viewModel.nodes(in: folderURL).isEmpty {
                refreshableStateView(
                    title: folderURL == nil ? "No Supported Files" : "No Visible Items",
                    systemImage: folderURL == nil ? "doc.text.magnifyingglass" : "folder",
                    message: folderURL == nil
                        ? "This workspace does not contain any supported files yet."
                        : "This folder does not contain any supported Markdown or text files."
                )
            } else {
                List {
                    Section {
                        ForEach(viewModel.nodes(in: folderURL)) { node in
                            WorkspaceFolderRow(
                                viewModel: viewModel,
                                node: node,
                                navigationMode: navigationMode
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.refreshFromPullToRefresh()
                }
            }
        }
        .navigationTitle(viewModel.title(for: folderURL))
        .searchable(text: searchQueryBinding, prompt: "Search Files")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("New File", systemImage: "plus") {
                    viewModel.presentCreateFile(in: folderURL)
                }
                .disabled(viewModel.isBusy)
                .accessibilityLabel("New Text File")
                .accessibilityHint("Creates a Markdown or text file in the current folder.")

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
            Text("Create a new Markdown or text file in this folder.")
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

private struct WorkspaceFolderRow: View {
    let viewModel: WorkspaceViewModel
    let node: WorkspaceNode
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        switch node {
        case .folder:
            if navigationMode.usesValueNavigationLinks == false {
                Button {
                    viewModel.openFolder(node.url)
                } label: {
                    WorkspaceRowView(node: node, isSelected: false)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: AppRoute.folder(node.url)) {
                    WorkspaceRowView(node: node, isSelected: false)
                }
            }
        case .file:
            if navigationMode.usesValueNavigationLinks == false {
                Button {
                    viewModel.openDocument(node.url)
                } label: {
                    WorkspaceRowView(node: node, isSelected: viewModel.isSelected(node))
                }
                .buttonStyle(.plain)
                .contextMenu {
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
                .swipeActions {
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
            } else {
                NavigationLink(value: AppRoute.editor(node.url)) {
                    WorkspaceRowView(node: node, isSelected: viewModel.isSelected(node))
                }
                .contextMenu {
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
                .swipeActions {
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
                return container.workspaceViewModel
            }(),
            folderURL: nil,
            showsSettingsButton: true,
            navigationMode: .stackPath
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
                return container.workspaceViewModel
            }(),
            folderURL: PreviewSampleData.deepWorkspaceRootFolderURL,
            showsSettingsButton: false,
            navigationMode: .stackPath
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
                return container.workspaceViewModel
            }(),
            folderURL: nil,
            showsSettingsButton: true,
            navigationMode: .stackPath
        )
    }
}
