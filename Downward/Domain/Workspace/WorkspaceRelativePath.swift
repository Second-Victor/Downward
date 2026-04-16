import Foundation

/// Defines the app's canonical file identity as a workspace-relative path.
enum WorkspaceRelativePath {
    nonisolated static func make(
        for itemURL: URL,
        within workspaceRootURL: URL
    ) -> String? {
        let itemComponents = itemURL.standardizedFileURL.pathComponents
        let rootComponents = workspaceRootURL.standardizedFileURL.pathComponents

        guard
            itemComponents.count > rootComponents.count,
            itemComponents.starts(with: rootComponents)
        else {
            return nil
        }

        return itemComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }

    nonisolated static func resolve(
        _ relativePath: String,
        within workspaceRootURL: URL
    ) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(workspaceRootURL.standardizedFileURL) { partialURL, component in
                partialURL.appending(path: String(component))
            }
    }
}
