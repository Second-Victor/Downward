import Foundation

/// Safety policy for opening workspace documents into the in-memory editor buffer.
enum DocumentOpenPolicy {
    nonisolated static let maximumReadableFileSize = 5 * 1024 * 1024
    nonisolated static let maximumReadableFileSizeDescription = "5 MB"

    nonisolated static func validateReadableFileSize(
        _ fileSize: Int?,
        displayName: String
    ) throws {
        guard let fileSize else {
            throw AppError.documentOpenFailed(
                name: displayName,
                details: "Downward could not verify the file size before opening it safely."
            )
        }

        guard fileSize <= maximumReadableFileSize else {
            throw AppError.documentOpenFailed(
                name: displayName,
                details: "This file is too large to open safely. Downward can open text files up to \(maximumReadableFileSizeDescription)."
            )
        }
    }

    nonisolated static func fileSize(from resourceValues: URLResourceValues, url: URL) -> Int? {
        if let resourceFileSize = resourceValues.fileSize {
            return resourceFileSize
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return (attributes[.size] as? NSNumber)?.intValue
    }
}
