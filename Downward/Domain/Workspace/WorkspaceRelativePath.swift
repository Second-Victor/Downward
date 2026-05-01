import Foundation

/// Defines the app's canonical file identity as a workspace-relative path.
enum WorkspaceRelativePath {
    /// Workspace boundary policy:
    /// - relative-path identity is only trusted after the descendant passes a stronger boundary check
    /// - reject any symlinked descendant entirely, even if it resolves back inside the workspace
    /// - require existing descendants to resolve under the canonical workspace root
    /// - allow equivalent root aliases to derive the same canonical relative identity when the
    ///   ancestor walk still reaches the real workspace root without crossing a symlinked escape
    /// - allow non-existing mutation targets only when every existing ancestor stays in-root and is not a symlink
    nonisolated static func make(
        for itemURL: URL,
        within workspaceRootURL: URL
    ) -> String? {
        guard
            let relativeComponents = validatedRelativePathComponents(
                forExistingItemAt: itemURL,
                within: workspaceRootURL
            )
        else {
            return nil
        }

        return relativeComponents.joined(separator: "/")
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

    nonisolated static func resolveExisting(
        _ relativePath: String,
        within workspaceRootURL: URL
    ) -> URL? {
        resolveValidated(
            relativePath,
            within: workspaceRootURL,
            requireExistingLeaf: true
        )
    }

    nonisolated static func resolveCandidate(
        _ relativePath: String,
        within workspaceRootURL: URL
    ) -> URL? {
        resolveValidated(
            relativePath,
            within: workspaceRootURL,
            requireExistingLeaf: false
        )
    }

    nonisolated static func containsExistingItem(
        at itemURL: URL,
        within workspaceRootURL: URL
    ) -> Bool {
        validatedRelativePathComponents(
            forExistingItemAt: itemURL,
            within: workspaceRootURL
        ) != nil
    }

    nonisolated private static func validatedRelativePathComponents(
        forExistingItemAt itemURL: URL,
        within workspaceRootURL: URL
    ) -> [String]? {
        guard let relativeComponents = ancestorRelativePathComponents(
            forExistingItemAt: itemURL,
            within: workspaceRootURL
        ) else {
            return nil
        }

        guard validateDescendantComponents(
            relativeComponents,
            within: workspaceRootURL,
            requireExistingLeaf: true
        ) != nil else {
            return nil
        }

        return relativeComponents
    }

    nonisolated private static func ancestorRelativePathComponents(
        forExistingItemAt itemURL: URL,
        within workspaceRootURL: URL
    ) -> [String]? {
        let standardizedRootURL = workspaceRootURL.standardizedFileURL
        let canonicalRootURL = workspaceRootURL.resolvingSymlinksInPath().standardizedFileURL
        var currentURL = itemURL.standardizedFileURL
        var relativeComponents: [String] = []

        while true {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try currentURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            } catch {
                return nil
            }

            guard resourceValues.isSymbolicLink != true else {
                return nil
            }

            let canonicalCurrentURL = currentURL.resolvingSymlinksInPath().standardizedFileURL
            if currentURL == standardizedRootURL || canonicalCurrentURL == canonicalRootURL {
                return relativeComponents.isEmpty ? nil : relativeComponents
            }

            let parentURL = currentURL.deletingLastPathComponent().standardizedFileURL
            guard parentURL != currentURL else {
                return nil
            }

            relativeComponents.insert(currentURL.lastPathComponent, at: 0)
            currentURL = parentURL
        }
    }

    nonisolated private static func resolveValidated(
        _ relativePath: String,
        within workspaceRootURL: URL,
        requireExistingLeaf: Bool
    ) -> URL? {
        guard
            let relativeComponents = sanitizedRelativePathComponents(from: relativePath)
        else {
            return nil
        }

        return validateDescendantComponents(
            relativeComponents,
            within: workspaceRootURL,
            requireExistingLeaf: requireExistingLeaf
        )
    }

    nonisolated private static func sanitizedRelativePathComponents(
        from relativePath: String
    ) -> [String]? {
        guard relativePath.hasPrefix("/") == false else {
            return nil
        }

        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard
            components.isEmpty == false,
            components.allSatisfy(isSafeRelativePathComponent)
        else {
            return nil
        }

        return components
    }

    /// Relative route strings are app-owned identity, not user-entered URLs. Reject path-control
    /// components both literally and after percent decoding so encoded escapes cannot be
    /// reinterpreted by a later filesystem boundary.
    nonisolated private static func isSafeRelativePathComponent(_ component: String) -> Bool {
        guard component != "." && component != ".." else {
            return false
        }

        guard let decodedComponent = component.removingPercentEncoding else {
            return true
        }

        return decodedComponent != "."
            && decodedComponent != ".."
            && decodedComponent.contains("/") == false
    }

    nonisolated private static func validateDescendantComponents(
        _ relativeComponents: [String],
        within workspaceRootURL: URL,
        requireExistingLeaf: Bool
    ) -> URL? {
        let canonicalRootURL = workspaceRootURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRootComponents = canonicalRootURL.pathComponents
        let fileManager = FileManager.default
        var currentURL = workspaceRootURL.standardizedFileURL

        for (index, component) in relativeComponents.enumerated() {
            let nextURL = currentURL.appending(path: component).standardizedFileURL
            let isLastComponent = index == relativeComponents.count - 1

            guard fileManager.fileExists(atPath: nextURL.path) else {
                guard requireExistingLeaf == false, isLastComponent else {
                    return nil
                }

                let canonicalParentURL = currentURL.resolvingSymlinksInPath().standardizedFileURL
                guard isContained(
                    canonicalParentURL,
                    within: canonicalRootComponents,
                    allowEqual: true
                ) else {
                    return nil
                }

                return nextURL
            }

            let resourceValues: URLResourceValues
            do {
                resourceValues = try nextURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            } catch {
                return nil
            }

            guard resourceValues.isSymbolicLink != true else {
                return nil
            }

            let canonicalNextURL = nextURL.resolvingSymlinksInPath().standardizedFileURL
            guard isContained(
                canonicalNextURL,
                within: canonicalRootComponents,
                allowEqual: false
            ) else {
                return nil
            }

            currentURL = nextURL
        }

        return currentURL
    }

    nonisolated private static func isContained(
        _ candidateURL: URL,
        within rootComponents: [String],
        allowEqual: Bool
    ) -> Bool {
        let candidateComponents = candidateURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else {
            return false
        }

        return allowEqual || candidateComponents.count > rootComponents.count
    }
}
