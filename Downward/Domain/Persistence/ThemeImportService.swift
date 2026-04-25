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
                throw ThemeImportError.fileTooLarge(
                    actualFileSize: fileSize,
                    maximumFileSize: maximumFileSize
                )
            }

            let data = try Data(contentsOf: url)
            return try ThemeExchangeDocument(data: data).themes
        }.value
    }
}

enum ThemeImportError: LocalizedError, Equatable {
    case fileTooLarge(actualFileSize: Int, maximumFileSize: Int)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(actualFileSize, maximumFileSize):
            let actualSize = Self.formattedMegabytes(for: actualFileSize)
            let maximumSize = Self.formattedMegabytes(for: maximumFileSize)
            return "The selected file is \(actualSize), which exceeds the \(maximumSize) import limit."
        }
    }

    private static func formattedMegabytes(for byteCount: Int) -> String {
        let megabytes = Double(byteCount) / Double(1024 * 1024)
        return String(format: "%.1f MB", megabytes)
    }
}
