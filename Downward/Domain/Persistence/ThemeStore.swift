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
    private let entitlements: any ThemeEntitlementProviding
    private let bundledPremiumThemeIDs: Set<UUID>
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
        persistThemes: PersistThemes? = nil,
        entitlements: any ThemeEntitlementProviding = ThemeEntitlementStore(),
        bundledPremiumThemes: [CustomTheme] = ThemeStore.bundledPremiumThemes
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.loadData = loadData
        self.persistenceService = persistenceService
        self.persistThemes = persistThemes ?? { themes, fileURL in
            try await persistenceService.persistThemes(themes, to: fileURL)
        }
        self.entitlements = entitlements
        self.bundledPremiumThemeIDs = Set(bundledPremiumThemes.map(\.id))
        self.loadTask = Task { [fileURL = self.fileURL, loadData, persistenceService, bundledPremiumThemes, weak self] in
            let result = await persistenceService.loadThemes(from: fileURL, loadData: loadData)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                self.themes = Self.mergingBundledPremiumThemes(
                    bundledPremiumThemes,
                    with: result.themes
                )
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
        guard hasUnlockedThemes else {
            lastError = ThemeEntitlementGate.lockedMessage
            return false
        }

        if themes.contains(where: { $0.id != theme.id && $0.name.localizedCaseInsensitiveCompare(theme.name) == .orderedSame }) {
            lastError = "A theme named \"\(theme.name)\" already exists."
            return false
        }

        return await persist(themes + [theme])
    }

    @discardableResult
    func update(_ theme: CustomTheme) async -> Bool {
        guard hasUnlockedThemes else {
            lastError = ThemeEntitlementGate.lockedMessage
            return false
        }

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
        guard hasUnlockedThemes else {
            lastError = ThemeEntitlementGate.lockedMessage
            return false
        }

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
        await loadTask?.value

        guard hasUnlockedThemes else {
            lastError = ThemeEntitlementGate.lockedMessage
            return false
        }

        guard bundledPremiumThemeIDs.contains(id) == false else {
            lastError = "Bundled Extra Themes cannot be deleted."
            return false
        }

        let updatedThemes = themes.filter { $0.id != id }
        guard updatedThemes.count != themes.count else {
            return false
        }

        return await persist(updatedThemes)
    }

    func canDeleteTheme(id: UUID) -> Bool {
        hasUnlockedThemes && bundledPremiumThemeIDs.contains(id) == false && theme(withID: id) != nil
    }

    func theme(withID id: UUID) -> CustomTheme? {
        themes.first { $0.id == id }
    }

    var hasUnlockedThemes: Bool {
        entitlements.hasUnlockedThemes
    }

    var canRestoreThemePurchases: Bool {
        entitlements.canRestoreThemePurchases
    }

    func purchaseSupporterUnlock() async {
        await entitlements.purchaseSupporterUnlock()

        if hasUnlockedThemes {
            lastError = nil
        } else {
            lastError = "Supporter purchases are not available yet."
        }
    }

    func restoreThemePurchases() async {
        await entitlements.restoreThemePurchases()
    }

    func canSelectTheme(withID rawValue: String) -> Bool {
        if EditorTheme.builtIn.contains(where: { $0.id == rawValue }) {
            return true
        }

        guard let uuid = UUID(uuidString: rawValue) else {
            return false
        }

        return hasUnlockedThemes && theme(withID: uuid) != nil
    }

    func waitForInitialLoad() async {
        await loadTask?.value
    }

    func resolve(_ rawValue: String) -> EditorTheme {
        if let builtIn = EditorTheme.builtIn.first(where: { $0.id == rawValue }) {
            return builtIn
        }

        if let uuid = UUID(uuidString: rawValue),
           hasUnlockedThemes,
           let customTheme = theme(withID: uuid) {
            return EditorTheme(from: customTheme)
        }

        if UUID(uuidString: rawValue) != nil {
            guard hasUnlockedThemes else {
                return .adaptive
            }

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

    private static func mergingBundledPremiumThemes(
        _ bundledPremiumThemes: [CustomTheme],
        with persistedThemes: [CustomTheme]
    ) -> [CustomTheme] {
        let persistedThemesByID = Dictionary(
            persistedThemes.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let bundledThemeIDs = Set(bundledPremiumThemes.map(\.id))
        var mergedThemes = bundledPremiumThemes.map { persistedThemesByID[$0.id] ?? $0 }
        mergedThemes.append(
            contentsOf: persistedThemes.filter { bundledThemeIDs.contains($0.id) == false }
        )
        return mergedThemes
    }
}

extension ThemeStore {
    static let bundledPremiumThemes: [CustomTheme] = [
        CustomTheme(
            id: UUID(uuid: (
                0x11, 0x01, 0x91, 0x26, 0x7D, 0xF8, 0x47, 0x5F,
                0xB1, 0x32, 0xA5, 0x3F, 0x46, 0xED, 0xAE, 0x89
            )),
            name: "Monokai Light",
            background: HexColor(hex: "#F2EDEC"),
            text: HexColor(hex: "#231D21"),
            tint: HexColor(hex: "#379FD2"),
            boldItalicMarker: HexColor(hex: "#E25B75"),
            strikethrough: HexColor(hex: "#563FC1"),
            inlineCode: HexColor(hex: "#382E34"),
            codeBackground: HexColor(hex: "#E3DDDD"),
            horizontalRule: HexColor(hex: "#FF9414"),
            checkboxUnchecked: HexColor(hex: "#D83F3F"),
            checkboxChecked: HexColor(hex: "#2BA34C")
        ),
        CustomTheme(
            id: UUID(uuid: (
                0x0A, 0xA6, 0x59, 0xD3, 0x44, 0x9C, 0x47, 0xAF,
                0x8C, 0x1D, 0x6F, 0xA2, 0x36, 0x8D, 0x51, 0x18
            )),
            name: "Monokai",
            background: HexColor(hex: "#272822"),
            text: HexColor(hex: "#FFFFFF"),
            tint: HexColor(hex: "#70EEFC"),
            boldItalicMarker: HexColor(hex: "#EA3378"),
            strikethrough: HexColor(hex: "#BD8AF8"),
            inlineCode: HexColor(hex: "#E2E2E2"),
            codeBackground: HexColor(hex: "#3C3D36"),
            horizontalRule: HexColor(hex: "#FF9414"),
            checkboxUnchecked: HexColor(hex: "#FF4B4B"),
            checkboxChecked: HexColor(hex: "#AEEB49")
        ),
        CustomTheme(
            id: UUID(uuid: (
                0x07, 0x0D, 0x47, 0xAA, 0x30, 0x5A, 0x4C, 0x35,
                0x82, 0xA4, 0x82, 0xAC, 0xA3, 0x43, 0x4A, 0xAE
            )),
            name: "Solarized",
            background: HexColor(hex: "#FCF6E5"),
            text: HexColor(hex: "#173541"),
            tint: HexColor(hex: "#4689CC"),
            boldItalicMarker: HexColor(hex: "#FF6129"),
            strikethrough: HexColor(hex: "#C24480"),
            inlineCode: HexColor(hex: "#6D7C81"),
            codeBackground: HexColor(hex: "#EDE8D7"),
            horizontalRule: HexColor(hex: "#519F98"),
            checkboxUnchecked: HexColor(hex: "#CB4239"),
            checkboxChecked: HexColor(hex: "#89982E")
        ),
        CustomTheme(
            id: UUID(uuid: (
                0xA8, 0x40, 0x5B, 0x09, 0x1B, 0x56, 0x44, 0x19,
                0xB6, 0xF7, 0x18, 0xCB, 0x89, 0x22, 0x1A, 0x76
            )),
            name: "OLED Midnight",
            background: HexColor(hex: "#000000"),
            text: HexColor(hex: "#EAF2FF"),
            tint: HexColor(hex: "#63D2FF"),
            boldItalicMarker: HexColor(hex: "#9B8CFF"),
            strikethrough: HexColor(hex: "#77808C"),
            inlineCode: HexColor(hex: "#E7F0FF"),
            codeBackground: HexColor(hex: "#101216"),
            horizontalRule: HexColor(hex: "#2A2F38"),
            checkboxUnchecked: HexColor(hex: "#FF5C7A"),
            checkboxChecked: HexColor(hex: "#35D07F")
        ),
        CustomTheme(
            id: UUID(uuid: (
                0xC4, 0x6D, 0x83, 0x30, 0x6B, 0x5E, 0x4A, 0xEF,
                0x95, 0x0F, 0x4D, 0xA9, 0x1C, 0xF6, 0x57, 0x2B
            )),
            name: "Sepia Paper",
            background: HexColor(hex: "#F5E9D0"),
            text: HexColor(hex: "#3B2A1E"),
            tint: HexColor(hex: "#8A5A2B"),
            boldItalicMarker: HexColor(hex: "#B36B3C"),
            strikethrough: HexColor(hex: "#8A6F5A"),
            inlineCode: HexColor(hex: "#4A3425"),
            codeBackground: HexColor(hex: "#E8D6B8"),
            horizontalRule: HexColor(hex: "#C3A47D"),
            checkboxUnchecked: HexColor(hex: "#B5473A"),
            checkboxChecked: HexColor(hex: "#6D8A3A")
        ),
        CustomTheme(
            id: UUID(uuid: (
                0x36, 0x04, 0x9F, 0xB2, 0xB1, 0x98, 0x49, 0x99,
                0x8E, 0x66, 0xF3, 0xD5, 0x70, 0xC8, 0xE3, 0x1A
            )),
            name: "Forest",
            background: HexColor(hex: "#0F1F18"),
            text: HexColor(hex: "#DDEBDD"),
            tint: HexColor(hex: "#75C77B"),
            boldItalicMarker: HexColor(hex: "#B9D77A"),
            strikethrough: HexColor(hex: "#8EA79A"),
            inlineCode: HexColor(hex: "#E2F3D1"),
            codeBackground: HexColor(hex: "#192B22"),
            horizontalRule: HexColor(hex: "#3E6B50"),
            checkboxUnchecked: HexColor(hex: "#D96B5F"),
            checkboxChecked: HexColor(hex: "#7BD88F")
        ),
        CustomTheme(
            id: UUID(uuid: (
                0x72, 0x4F, 0x60, 0xD1, 0x89, 0x61, 0x4F, 0x27,
                0x93, 0xDF, 0x23, 0x85, 0xBA, 0x4A, 0x3E, 0x90
            )),
            name: "Polar Night",
            background: HexColor(hex: "#2E3440"),
            text: HexColor(hex: "#D8DEE9"),
            tint: HexColor(hex: "#88C0D0"),
            boldItalicMarker: HexColor(hex: "#B48EAD"),
            strikethrough: HexColor(hex: "#81A1C1"),
            inlineCode: HexColor(hex: "#EBCB8B"),
            codeBackground: HexColor(hex: "#3B4252"),
            horizontalRule: HexColor(hex: "#4C566A"),
            checkboxUnchecked: HexColor(hex: "#BF616A"),
            checkboxChecked: HexColor(hex: "#A3BE8C")
        )
    ]
}
