import Foundation

struct ThemeImportService: Sendable {
    private let maximumFileSize: Int

    init(maximumFileSize: Int = 5 * 1024 * 1024) {
        self.maximumFileSize = maximumFileSize
    }

    func loadThemes(from url: URL) async throws -> [CustomTheme] {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let maximumFileSize = maximumFileSize
        return try await Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int ?? 0
            guard fileSize <= maximumFileSize else {
                throw ThemeImportError.fileTooLarge(maximumFileSize: maximumFileSize)
            }

            let data = try Data(contentsOf: url)
            return try ThemeExchangeDocument(data: data).themes
        }.value
    }
}

enum ThemeImportError: LocalizedError, Equatable {
    case fileTooLarge(maximumFileSize: Int)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(maximumFileSize):
            let megabytes = maximumFileSize / (1024 * 1024)
            return "The theme file is too large to import (maximum \(megabytes) MB)."
        }
    }
}
