import Foundation

actor ThemePersistenceService {
    typealias LoadData = @Sendable (URL) async throws -> Data

    struct LoadResult: Sendable {
        let themes: [CustomTheme]
        let errorMessage: String?
    }

    func loadThemes(from fileURL: URL, loadData: @escaping LoadData) async -> LoadResult {
        let path = fileURL.path(percentEncoded: false)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return LoadResult(themes: [], errorMessage: nil)
        }

        guard isDirectory.boolValue == false else {
            return LoadResult(
                themes: [],
                errorMessage: "Custom themes could not be loaded because the storage path is a directory."
            )
        }

        do {
            let data = try await loadData(fileURL)
            return LoadResult(
                themes: try JSONDecoder().decode([CustomTheme].self, from: data),
                errorMessage: nil
            )
        } catch let decodingError as DecodingError {
            return LoadResult(
                themes: [],
                errorMessage: "Custom themes could not be decoded: \(decodingError.localizedDescription)"
            )
        } catch {
            return LoadResult(
                themes: [],
                errorMessage: "Custom themes could not be read: \(error.localizedDescription)"
            )
        }
    }

    func persistThemes(_ themes: [CustomTheme], to fileURL: URL) throws {
        try prepareStorageLocation(for: fileURL)
        let data = try JSONEncoder().encode(themes)
        try data.write(to: fileURL, options: .atomic)
    }

    private func prepareStorageLocation(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let path = fileURL.path(percentEncoded: false)
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists, userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: "The custom theme storage path is a directory."
            ])
        }
    }
}
