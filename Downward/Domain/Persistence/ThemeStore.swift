import Foundation
import Observation

@Observable
@MainActor
final class ThemeStore {
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
    private var loadTask: Task<Void, Never>?

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
        persistenceService: ThemePersistenceService = ThemePersistenceService()
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.loadData = loadData
        self.persistenceService = persistenceService
        self.loadTask = Task { [fileURL = self.fileURL, loadData, persistenceService] in
            let result = await persistenceService.loadThemes(from: fileURL, loadData: loadData)
            await MainActor.run {
                self.themes = result.themes
                self.lastError = result.errorMessage
                self.loadState = result.errorMessage == nil ? .loaded : .failed
            }
        }
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
                    lastError = "A theme named \"\(importedTheme.name)\" already exists."
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
        let previousThemes = themes
        themes = updatedThemes
        do {
            try await persistenceService.persistThemes(updatedThemes, to: fileURL)
            lastError = nil
            return true
        } catch {
            themes = previousThemes
            lastError = "Could not save custom themes: \(error.localizedDescription)"
            return false
        }
    }
}
