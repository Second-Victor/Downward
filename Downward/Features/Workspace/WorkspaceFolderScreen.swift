import SwiftUI

struct WorkspaceFolderScreen: View {
    let viewModel: WorkspaceViewModel
    let showsSettingsButton: Bool
    let navigationMode: WorkspaceNavigationMode

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
                if navigationMode == .splitSidebar {
                List {
                    WorkspaceTreeRows(
                        viewModel: viewModel,
                        nodes: viewModel.nodes,
                        parentRelativePath: nil,
                            depth: 0,
                            navigationMode: navigationMode
                        )
                    }
                    .listStyle(.sidebar)
                    .refreshable {
                        await viewModel.refreshFromPullToRefresh()
                    }
                } else {
                    List {
                        Section {
                            WorkspaceTreeRows(
                                viewModel: viewModel,
                                nodes: viewModel.nodes,
                                parentRelativePath: nil,
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
        }
        .navigationTitle(viewModel.workspaceTitle)
        .searchable(text: searchQueryBinding, prompt: "Search Files")
        .toolbar {
            if showsSettingsButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.showSettings()
                    } label: {
                        GradientIconLabel("Settings", systemName: "gearshape", color: .accentColor)
                    }
                    .disabled(viewModel.isBusy)
                    .accessibilityHint("Shows workspace management options.")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.presentCreateFile(in: nil)
                    } label: {
                        GradientIconLabel("New File", systemName: "doc.badge.plus", color: .accentColor)
                    }
                    Button {
                        viewModel.presentCreateFolder(in: nil)
                    } label: {
                        GradientIconLabel("New Folder", systemName: "folder.badge.plus", color: .accentColor)
                    }
                } label: {
                    GradientIconLabel("Add", systemName: "plus", color: .accentColor)
                }
                .disabled(viewModel.isBusy)
                .accessibilityLabel("Add Item")
                .accessibilityHint("Creates a new file or folder in the workspace root.")
            }
        }
        .alert(viewModel.createPromptTitle, isPresented: createPromptBinding) {
            TextField(viewModel.createPromptFieldTitle, text: createItemNameBinding)

            Button(viewModel.createPromptActionTitle) {
                viewModel.createItem()
            }
            .disabled(viewModel.createItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {
                viewModel.cancelCreateItem()
            }
        } message: {
            Text(viewModel.createPromptMessage)
        }
        .alert(viewModel.renamePromptTitle, isPresented: renamePromptBinding) {
            TextField(viewModel.renamePromptFieldTitle, text: renameItemNameBinding)

            Button("Rename") {
                viewModel.renameItem()
            }
            .disabled(viewModel.renameItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {
                viewModel.cancelRename()
            }
        } message: {
            Text("Rename \(viewModel.pendingRenameTitle).")
        }
        .sheet(isPresented: moveSheetBinding) {
            NavigationStack {
                List(viewModel.moveDestinations) { destination in
                    Button {
                        viewModel.moveItem(toFolderRelativePath: destination.relativePath)
                    } label: {
                        HStack(spacing: 10) {
                            if destination.nestingLevel > 0 {
                                Color.clear
                                    .frame(width: CGFloat(destination.nestingLevel) * 18)
                            }

                            Text(destination.title)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 32, alignment: .leading)
                    }
                    .disabled(viewModel.isBusy)
                    .buttonStyle(.plain)
                }
                .navigationTitle(viewModel.moveSheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            viewModel.cancelMove()
                        }
                    }
                }
            }
        }
    }

    private var createPromptBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingCreatePrompt },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelCreateItem()
                }
            }
        )
    }

    private var createItemNameBinding: Binding<String> {
        Binding(
            get: { viewModel.createItemName },
            set: { viewModel.createItemName = $0 }
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

    private var renameItemNameBinding: Binding<String> {
        Binding(
            get: { viewModel.renameItemName },
            set: { viewModel.renameItemName = $0 }
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.searchQuery = $0 }
        )
    }

    private var moveSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingMoveSheet },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelMove()
                }
            }
        )
    }

    private func refreshableStateView(title: String, systemImage: String, message: String) -> some View {
        ScrollView {
            GradientContentUnavailableView(
                title,
                systemName: systemImage,
                color: .secondary
            ) {
                Text(message)
            }
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
    let parentRelativePath: String?
    let depth: Int
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        ForEach(nodes) { node in
            let relativePath = joinedRelativePath(
                parentRelativePath,
                component: node.url.lastPathComponent
            )
            WorkspaceTreeRow(
                viewModel: viewModel,
                node: node,
                relativePath: relativePath,
                depth: depth,
                navigationMode: navigationMode
            )
            if
                case let .folder(folder) = node,
                viewModel.isFolderExpanded(atRelativePath: relativePath)
            {
                WorkspaceTreeRows(
                    viewModel: viewModel,
                    nodes: folder.children,
                    parentRelativePath: relativePath,
                    depth: depth + 1,
                    navigationMode: navigationMode
                )
            }
        }
    }

    private func joinedRelativePath(_ parentRelativePath: String?, component: String) -> String {
        guard let parentRelativePath, parentRelativePath.isEmpty == false else {
            return component
        }

        return "\(parentRelativePath)/\(component)"
    }
}

private struct WorkspaceTreeRow: View {
    let viewModel: WorkspaceViewModel
    let node: WorkspaceNode
    let relativePath: String
    let depth: Int
    let navigationMode: WorkspaceNavigationMode

    var body: some View {
        switch node {
        case .folder:
            folderRow
        case .file:
            fileRow
        }
    }

    @ViewBuilder
    private var folderRow: some View {
        if case let .folder(folder) = node {
            Button {
                viewModel.toggleFolderExpansion(atRelativePath: relativePath)
            } label: {
                WorkspaceRowView(
                    node: node,
                    hierarchyDepth: depth,
                    folderDisclosureState: viewModel.isFolderExpanded(atRelativePath: relativePath) ? .expanded : .collapsed
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    viewModel.presentCreateFile(in: folder.url)
                } label: {
                    GradientIconLabel("New File", systemName: "plus", color: .accentColor)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("New File in \(node.displayName)")
                .accessibilityHint("Creates a text or source file inside this folder.")

                Button {
                    viewModel.presentCreateFolder(in: folder.url)
                } label: {
                    GradientIconLabel("New Folder", systemName: "folder.badge.plus", color: .accentColor)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("New Folder in \(node.displayName)")
                .accessibilityHint("Creates a folder inside this folder.")

                Button {
                    viewModel.presentRename(for: node)
                } label: {
                    GradientIconLabel("Rename", systemName: "pencil", color: .accentColor)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("Rename \(node.displayName)")
                .accessibilityHint("Changes the folder name.")

                Button {
                    viewModel.presentMove(for: node)
                } label: {
                    GradientIconLabel("Move", systemName: "folder", color: .blue)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("Move \(node.displayName)")
                .accessibilityHint("Moves this folder to another folder in the workspace.")

                Button(role: .destructive) {
                    viewModel.presentDelete(for: node)
                } label: {
                    GradientIconLabel("Delete", systemName: "trash", color: .red)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("Delete \(node.displayName)")
                .accessibilityHint("Deletes this folder and its contents from the workspace.")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                folderSwipeActions
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: deleteDialogBinding,
                titleVisibility: .visible
            ) {
                Button("Delete \(node.displayName)", role: .destructive) {
                    viewModel.deleteItem()
                }

                Button("Cancel", role: .cancel) {
                    viewModel.cancelDelete()
                }
            } message: {
                Text(deleteDialogMessage)
            }
        }
    }

    @ViewBuilder
    private var fileRow: some View {
        if navigationMode.usesValueNavigationLinks {
            NavigationLink(value: AppRoute.trustedEditor(node.url, relativePath)) {
                WorkspaceRowView(
                    node: node,
                    hierarchyDepth: depth
                )
            }
            .contextMenu {
                fileContextMenu
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                fileSwipeActions
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: deleteDialogBinding,
                titleVisibility: .visible
            ) {
                Button("Delete \(node.displayName)", role: .destructive) {
                    viewModel.deleteItem()
                }

                Button("Cancel", role: .cancel) {
                    viewModel.cancelDelete()
                }
            } message: {
                Text(deleteDialogMessage)
            }
        } else {
            Button {
                viewModel.openDocument(
                    relativePath: relativePath,
                    preferredURL: node.url
                )
            } label: {
                WorkspaceRowView(
                    node: node,
                    hierarchyDepth: depth
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                fileContextMenu
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                fileSwipeActions
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: deleteDialogBinding,
                titleVisibility: .visible
            ) {
                Button("Delete \(node.displayName)", role: .destructive) {
                    viewModel.deleteItem()
                }

                Button("Cancel", role: .cancel) {
                    viewModel.cancelDelete()
                }
            } message: {
                Text(deleteDialogMessage)
            }
        }
    }

    @ViewBuilder
    private var fileContextMenu: some View {
        Button {
            if case .file = node {
                viewModel.presentMove(for: node)
            }
        } label: {
            GradientIconLabel("Move", systemName: "folder", color: .blue)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .accessibilityLabel("Move \(node.displayName)")
        .accessibilityHint("Moves this file to another folder in the workspace.")

        Button {
            if case .file = node {
                viewModel.presentRename(for: node)
            }
        } label: {
            GradientIconLabel("Rename", systemName: "pencil", color: .accentColor)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .accessibilityLabel("Rename \(node.displayName)")
        .accessibilityHint("Changes the file name.")

        Button(role: .destructive) {
            if case .file = node {
                viewModel.presentDelete(for: node)
            }
        } label: {
            GradientIconLabel("Delete", systemName: "trash", color: .red)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .accessibilityLabel("Delete \(node.displayName)")
        .accessibilityHint("Deletes this file from the workspace.")
    }

    @ViewBuilder
    private var fileSwipeActions: some View {
        Button {
            if case .file = node {
                viewModel.presentMove(for: node)
            }
        } label: {
            GradientIconLabel("Move", systemName: "folder", color: .blue)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.blue)

        Button {
            if case .file = node {
                viewModel.presentRename(for: node)
            }
        } label: {
            GradientIconLabel("Rename", systemName: "pencil", color: .accentColor)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.accentColor)

        Button {
            if case .file = node {
                viewModel.presentDelete(for: node)
            }
        } label: {
            GradientIconLabel("Delete", systemName: "trash", color: .red)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.red)
    }

    @ViewBuilder
    private var folderSwipeActions: some View {
        Button {
            if case .folder = node {
                viewModel.presentMove(for: node)
            }
        } label: {
            GradientIconLabel("Move", systemName: "folder", color: .blue)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.blue)

        Button {
            if case .folder = node {
                viewModel.presentRename(for: node)
            }
        } label: {
            GradientIconLabel("Rename", systemName: "pencil", color: .accentColor)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.accentColor)

        Button {
            if case .folder = node {
                viewModel.presentDelete(for: node)
            }
        } label: {
            GradientIconLabel("Delete", systemName: "trash", color: .red)
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.red)
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.isShowingDeleteConfirmation && viewModel.pendingDeleteNode?.url == node.url
            },
            set: { isPresented in
                guard isPresented == false, viewModel.pendingDeleteNode?.url == node.url else {
                    return
                }

                viewModel.cancelDelete()
            }
        )
    }

    private var deleteDialogTitle: String {
        node.isFolder ? "Delete Folder" : "Delete File"
    }

    private var deleteDialogMessage: String {
        if node.isFolder {
            return "This removes \(node.displayName) and its contents from the workspace."
        }

        return "This removes \(node.displayName) from the workspace."
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
                container.workspaceViewModel.expandFolderAndAncestors(at: PreviewSampleData.deepWorkspaceRootFolderURL)
                return container.workspaceViewModel
            }(),
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
                container.workspaceViewModel.expandFolderAndAncestors(at: PreviewSampleData.largeWorkspace.rootNodes[0].url)
                return container.workspaceViewModel
            }(),
            showsSettingsButton: true,
            navigationMode: .stackPath
        )
    }
}
