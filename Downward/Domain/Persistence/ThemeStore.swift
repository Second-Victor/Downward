import Foundation
import Observation

@Observable
@MainActor
final class ThemeStore {
    typealias PersistThemes = @Sendable ([CustomTheme], URL) async throws -> Void

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var themes: [CustomTheme] = []
    var lastError: String?
    private(set) var loadState: LoadState = .loading

    private let fileURL: URL
    private let loadData: ThemePersistenceService.LoadData
    private let persistenceService: ThemePersistenceService
    private let persistThemes: PersistThemes
    private var loadTask: Task<Void, Never>?
    private var persistenceTask: Task<PersistenceResult, Never>?
    private var persistenceGeneration = 0

    private enum PersistenceResult: Sendable {
        case success
        case failure(String)
    }

    private static let defaultFileURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = appSupport.appending(path: "Downward", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "custom-themes.json")
    }()

    init(
        fileURL: URL? = nil,
        loadData: @escaping ThemePersistenceService.LoadData = { url in try Data(contentsOf: url) },
        persistenceService: ThemePersistenceService = ThemePersistenceService(),
        persistThemes: PersistThemes? = nil
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.loadData = loadData
        self.persistenceService = persistenceService
        self.persistThemes = persistThemes ?? { themes, fileURL in
            try await persistenceService.persistThemes(themes, to: fileURL)
        }
        self.loadTask = Task { [fileURL = self.fileURL, loadData, persistenceService, weak self] in
            let result = await persistenceService.loadThemes(from: fileURL, loadData: loadData)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                self.themes = result.themes
                self.lastError = result.errorMessage
                self.loadState = result.errorMessage == nil ? .loaded : .failed
            }
        }
    }

    isolated deinit {
        loadTask?.cancel()
        persistenceTask?.cancel()
    }

    @discardableResult
    func add(_ theme: CustomTheme) async -> Bool {
        if themes.contains(where: { $0.id != theme.id && $0.name.localizedCaseInsensitiveCompare(theme.name) == .orderedSame }) {
            lastError = "A theme named \"\(theme.name)\" already exists."
            return false
        }

        return await persist(themes + [theme])
    }

    @discardableResult
    func update(_ theme: CustomTheme) async -> Bool {
        guard let index = themes.firstIndex(where: { $0.id == theme.id }) else {
            return false
        }

        if themes.contains(where: { $0.id != theme.id && $0.name.localizedCaseInsensitiveCompare(theme.name) == .orderedSame }) {
            lastError = "A theme named \"\(theme.name)\" already exists."
            return false
        }

        var updatedThemes = themes
        updatedThemes[index] = theme
        return await persist(updatedThemes)
    }

    @discardableResult
    func importThemes(_ importedThemes: [CustomTheme]) async -> Bool {
        guard importedThemes.isEmpty == false else {
            lastError = "The selected JSON file did not contain any themes."
            return false
        }

        var updatedThemes = themes
        for importedTheme in importedThemes {
            if let index = updatedThemes.firstIndex(where: { $0.id == importedTheme.id }) {
                updatedThemes[index] = importedTheme
            } else {
                if updatedThemes.contains(where: {
                    $0.id != importedTheme.id &&
                    $0.name.localizedCaseInsensitiveCompare(importedTheme.name) == .orderedSame
                }) {
                    lastError = "Could not import \"\(importedTheme.name)\" because a different theme with that name already exists."
                    return false
                }

                updatedThemes.append(importedTheme)
            }
        }

        return await persist(updatedThemes)
    }

    @discardableResult
    func delete(id: UUID) async -> Bool {
        let updatedThemes = themes.filter { $0.id != id }
        guard updatedThemes.count != themes.count else {
            return false
        }

        return await persist(updatedThemes)
    }

    func theme(withID id: UUID) -> CustomTheme? {
        themes.first { $0.id == id }
    }

    func waitForInitialLoad() async {
        await loadTask?.value
    }

    func resolve(_ rawValue: String) -> EditorTheme {
        if let builtIn = EditorTheme.builtIn.first(where: { $0.id == rawValue }) {
            return builtIn
        }

        if let uuid = UUID(uuidString: rawValue),
           let customTheme = theme(withID: uuid) {
            return EditorTheme(from: customTheme)
        }

        if UUID(uuidString: rawValue) != nil {
            switch loadState {
            case .loading:
                return .loadingCustomTheme(id: rawValue)
            case .failed:
                return .failedCustomTheme(id: rawValue)
            case .loaded:
                break
            }
        }

        return .adaptive
    }

    @discardableResult
    private func persist(_ updatedThemes: [CustomTheme]) async -> Bool {
        await loadTask?.value
        _ = await persistenceTask?.value

        let previousThemes = themes
        themes = updatedThemes

        // Explicit theme mutations are store-owned user actions. Serialize writes so an earlier
        // save/import/delete cannot finish later and roll back a newer successful mutation.
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let persistThemes = self.persistThemes
        let fileURL = self.fileURL
        persistenceTask = Task {
            do {
                try await persistThemes(updatedThemes, fileURL)
                return .success
            } catch {
                return .failure("Could not save custom themes: \(error.localizedDescription)")
            }
        }

        let result = await persistenceTask?.value ?? .success
        if generation == persistenceGeneration {
            persistenceTask = nil
        }

        switch result {
        case .success:
            lastError = nil
            return true
        case let .failure(message):
            themes = previousThemes
            lastError = message
            return false
        }
    }
}
