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
                    Button("Settings", systemImage: "gearshape") {
                        viewModel.showSettings()
                    }
                    .disabled(viewModel.isBusy)
                    .accessibilityHint("Shows workspace management options.")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Add", systemImage: "plus") {
                    Button("New File", systemImage: "doc.badge.plus") {
                        viewModel.presentCreateFile(in: nil)
                    }
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        viewModel.presentCreateFolder(in: nil)
                    }
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(destination.title)
                                .foregroundStyle(.primary)
                            if let subtitle = destination.subtitle {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                Button("New File", systemImage: "plus") {
                    viewModel.presentCreateFile(in: folder.url)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("New File in \(node.displayName)")
                .accessibilityHint("Creates a Markdown, text, or JSON file inside this folder.")

                Button("New Folder", systemImage: "folder.badge.plus") {
                    viewModel.presentCreateFolder(in: folder.url)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("New Folder in \(node.displayName)")
                .accessibilityHint("Creates a folder inside this folder.")

                Button("Rename", systemImage: "pencil") {
                    viewModel.presentRename(for: node)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("Rename \(node.displayName)")
                .accessibilityHint("Changes the folder name.")

                Button("Move", systemImage: "folder") {
                    viewModel.presentMove(for: node)
                }
                .disabled(viewModel.areRowActionsDisabled)
                .accessibilityLabel("Move \(node.displayName)")
                .accessibilityHint("Moves this folder to another folder in the workspace.")

                Button("Delete", systemImage: "trash", role: .destructive) {
                    viewModel.presentDelete(for: node)
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
        Button("Move", systemImage: "folder") {
            if case .file = node {
                viewModel.presentMove(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .accessibilityLabel("Move \(node.displayName)")
        .accessibilityHint("Moves this file to another folder in the workspace.")

        Button("Rename", systemImage: "pencil") {
            if case .file = node {
                viewModel.presentRename(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .accessibilityLabel("Rename \(node.displayName)")
        .accessibilityHint("Changes the file name.")

        Button("Delete", systemImage: "trash", role: .destructive) {
            if case .file = node {
                viewModel.presentDelete(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .accessibilityLabel("Delete \(node.displayName)")
        .accessibilityHint("Deletes this file from the workspace.")
    }

    @ViewBuilder
    private var fileSwipeActions: some View {
        Button("Move", systemImage: "folder") {
            if case .file = node {
                viewModel.presentMove(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.blue)

        Button("Rename", systemImage: "pencil") {
            if case .file = node {
                viewModel.presentRename(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.accentColor)

        Button("Delete", systemImage: "trash") {
            if case .file = node {
                viewModel.presentDelete(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.red)
    }

    @ViewBuilder
    private var folderSwipeActions: some View {
        Button("Move", systemImage: "folder") {
            if case .folder = node {
                viewModel.presentMove(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.blue)

        Button("Rename", systemImage: "pencil") {
            if case .folder = node {
                viewModel.presentRename(for: node)
            }
        }
        .disabled(viewModel.areRowActionsDisabled)
        .tint(.accentColor)

        Button("Delete", systemImage: "trash") {
            if case .folder = node {
                viewModel.presentDelete(for: node)
            }
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
