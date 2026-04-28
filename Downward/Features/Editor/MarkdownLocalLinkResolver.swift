import Foundation

nonisolated enum MarkdownLinkDestination: Equatable {
    case external(URL)
    case local(String)
}

nonisolated enum MarkdownLocalLinkResolution: Equatable {
    case anchorOnly
    case target(relativePath: String, url: URL)
    case missing(displayPath: String)
    case unsupported(displayPath: String)
}

nonisolated enum MarkdownLocalLinkResolver {
    static func resolve(
        destination: String,
        from currentDocumentRelativePath: String,
        in snapshot: WorkspaceSnapshot
    ) -> MarkdownLocalLinkResolution {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .unsupported(displayPath: destination)
        }

        if trimmed.hasPrefix("#") {
            return .anchorOnly
        }

        guard MarkdownExternalLinkURL.url(forMarkdownDestination: trimmed) == nil else {
            return .unsupported(displayPath: trimmed)
        }

        guard hasURLScheme(trimmed) == false,
              trimmed.hasPrefix("/") == false,
              trimmed.hasPrefix("~") == false,
              trimmed.contains("\\") == false
        else {
            return .unsupported(displayPath: trimmed)
        }

        let pathPart = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard pathPart.isEmpty == false else {
            return .anchorOnly
        }

        guard pathPart.contains("?") == false else {
            return .unsupported(displayPath: trimmed)
        }

        let decodedPath = pathPart.removingPercentEncoding ?? pathPart
        guard decodedPath.isEmpty == false,
              let resolvedRelativePath = normalizedRelativePath(
                for: decodedPath,
                from: currentDocumentRelativePath
              )
        else {
            return .unsupported(displayPath: decodedPath)
        }

        let pathExtension = (resolvedRelativePath as NSString).pathExtension
        guard SupportedFileType.isSupportedExtension(pathExtension) else {
            return .unsupported(displayPath: resolvedRelativePath)
        }

        guard let url = snapshot.fileURL(forRelativePath: resolvedRelativePath) else {
            return .missing(displayPath: resolvedRelativePath)
        }

        return .target(relativePath: resolvedRelativePath, url: url)
    }

    private static func normalizedRelativePath(
        for linkPath: String,
        from currentDocumentRelativePath: String
    ) -> String? {
        var components = currentDocumentRelativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if components.isEmpty == false {
            components.removeLast()
        }

        for component in linkPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard components.isEmpty == false else {
                    return nil
                }
                components.removeLast()
            default:
                components.append(component)
            }
        }

        guard components.isEmpty == false else {
            return nil
        }

        return components.joined(separator: "/")
    }

    private static func hasURLScheme(_ destination: String) -> Bool {
        guard let colonIndex = destination.firstIndex(of: ":") else {
            return false
        }

        let scheme = destination[..<colonIndex]
        guard scheme.isEmpty == false else {
            return false
        }

        return scheme.allSatisfy { character in
            character.isLetter || character.isNumber || character == "+" || character == "-" || character == "."
        }
    }
}
