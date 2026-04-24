import Foundation

/// Central policy for file types that should appear in the workspace browser.
enum SupportedFileType: String, CaseIterable, Sendable {
    case markdown = "md"
    case markdownText = "markdown"
    case plainText = "txt"
    case json = "json"

    nonisolated static func isSupported(url: URL) -> Bool {
        guard url.hasDirectoryPath == false else {
            return false
        }

        return isSupportedExtension(url.pathExtension)
    }

    nonisolated static func isSupportedExtension(_ fileExtension: String) -> Bool {
        Self(rawValue: fileExtension.lowercased()) != nil
    }

}
