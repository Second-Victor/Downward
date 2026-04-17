import Foundation

protocol WorkspaceEnumerating: Sendable {
    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot
}

struct WorkspaceEnumerationDiagnostics: Equatable, Sendable {
    nonisolated let skippedDescendantPaths: [String]
}

/// Walks the workspace recursively, keeping all real folders while filtering files down to supported types.
struct LiveWorkspaceEnumerator: WorkspaceEnumerating {
    private let logger: DebugLogger?
    private let onDiagnostics: (@Sendable (WorkspaceEnumerationDiagnostics) -> Void)?

    nonisolated init(
        logger: DebugLogger? = nil,
        onDiagnostics: (@Sendable (WorkspaceEnumerationDiagnostics) -> Void)? = nil
    ) {
        self.logger = logger
        self.onDiagnostics = onDiagnostics
    }

    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        var skippedDescendantPaths: [String] = []
        let rootNodes = try makeNodes(
            in: rootURL,
            within: rootURL,
            allowsPartialFailure: false,
            skippedDescendantPaths: &skippedDescendantPaths
        ) ?? []
        emitDiagnosticsIfNeeded(skippedDescendantPaths)

        return WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: displayName,
            rootNodes: rootNodes,
            lastUpdated: Date()
        )
    }

    /// Enumeration policy:
    /// - unreadable workspace root: fail the refresh because there is no trustworthy workspace view
    /// - unreadable descendant: skip that node/subtree and keep remaining siblings
    /// - hidden/package descendants: skip intentionally because they are not part of the user-facing tree
    /// - symlinked or redirected descendants: skip entirely so the browser only surfaces real in-workspace nodes
    nonisolated private func makeNodes(
        in directoryURL: URL,
        within workspaceRootURL: URL,
        allowsPartialFailure: Bool,
        skippedDescendantPaths: inout [String]
    ) throws -> [WorkspaceNode]? {
        try Task.checkCancellation()

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .localizedNameKey,
            .nameKey,
            .contentModificationDateKey,
        ]

        let childURLs: [URL]
        do {
            childURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            )
        } catch {
            guard allowsPartialFailure else {
                throw error
            }

            guard Self.shouldSkipDescendantFailure(error) else {
                throw error
            }

            skippedDescendantPaths.append(
                Self.diagnosticPath(for: directoryURL, within: workspaceRootURL)
            )
            return nil
        }

        var nodes: [WorkspaceNode] = []
        nodes.reserveCapacity(childURLs.count)

        for childURL in childURLs {
            try Task.checkCancellation()

            let resourceValues: URLResourceValues
            do {
                resourceValues = try childURL.resourceValues(forKeys: resourceKeys)
            } catch {
                guard Self.shouldSkipDescendantFailure(error) else {
                    throw error
                }

                skippedDescendantPaths.append(
                    Self.diagnosticPath(for: childURL, within: workspaceRootURL)
                )
                continue
            }
            let displayName = resourceValues.localizedName ?? resourceValues.name ?? childURL.lastPathComponent

            guard Self.shouldSkipNode(
                at: childURL,
                within: workspaceRootURL,
                displayName: displayName,
                resourceValues: resourceValues
            ) == false else {
                continue
            }

            if resourceValues.isDirectory == true {
                guard let children = try makeNodes(
                    in: childURL,
                    within: workspaceRootURL,
                    allowsPartialFailure: true,
                    skippedDescendantPaths: &skippedDescendantPaths
                ) else {
                    continue
                }
                nodes.append(
                    .folder(
                        .init(
                            url: childURL,
                            displayName: displayName,
                            children: children
                        )
                    )
                )
                continue
            }

            guard resourceValues.isRegularFile == true else {
                continue
            }

            guard SupportedFileType.isSupported(url: childURL) else {
                continue
            }

            nodes.append(
                .file(
                    .init(
                        url: childURL,
                        displayName: displayName,
                        subtitle: nil,
                        modifiedAt: resourceValues.contentModificationDate
                    )
                )
            )
        }

        return nodes.sorted(by: workspaceNodeSortPredicate)
    }

    nonisolated private static func shouldSkipNode(
        at url: URL,
        within workspaceRootURL: URL,
        displayName: String,
        resourceValues: URLResourceValues
    ) -> Bool {
        if resourceValues.isHidden == true || displayName.hasPrefix(".") {
            return true
        }

        if resourceValues.isPackage == true {
            return true
        }

        if WorkspaceRelativePath.containsExistingItem(at: url, within: workspaceRootURL) == false {
            return true
        }

        return false
    }

    nonisolated private static func shouldSkipDescendantFailure(_ error: Error) -> Bool {
        (error is CancellationError) == false
    }

    nonisolated private func emitDiagnosticsIfNeeded(_ skippedDescendantPaths: [String]) {
        guard skippedDescendantPaths.isEmpty == false else {
            return
        }

        let diagnostics = WorkspaceEnumerationDiagnostics(
            skippedDescendantPaths: skippedDescendantPaths
        )
        onDiagnostics?(diagnostics)

        let previewPaths = skippedDescendantPaths.prefix(3).joined(separator: ", ")
        let suffix = skippedDescendantPaths.count > 3 ? ", ..." : ""
        logger?.log(
            category: "Workspace",
            "Partial enumeration skipped \(skippedDescendantPaths.count) descendant(s): \(previewPaths)\(suffix)"
        )
    }

    nonisolated private static func diagnosticPath(
        for url: URL,
        within workspaceRootURL: URL
    ) -> String {
        WorkspaceRelativePath.make(for: url, within: workspaceRootURL)
            ?? url.lastPathComponent
    }
}

struct StubWorkspaceEnumerator: WorkspaceEnumerating {
    let snapshot: WorkspaceSnapshot

    nonisolated func makeSnapshot(rootURL: URL, displayName: String) throws -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootURL: rootURL,
            displayName: displayName,
            rootNodes: snapshot.rootNodes,
            lastUpdated: snapshot.lastUpdated
        )
    }
}

nonisolated private func workspaceNodeSortPredicate(_ lhs: WorkspaceNode, _ rhs: WorkspaceNode) -> Bool {
    switch (lhs, rhs) {
    case (.folder, .file):
        return true
    case (.file, .folder):
        return false
    default:
        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
    }
}
