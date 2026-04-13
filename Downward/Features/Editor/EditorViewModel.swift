import Observation
import SwiftUI

@MainActor
@Observable
final class EditorViewModel {
    let session: AppSession
    let autosaveDelay: Duration
    var isShowingConflictResolution = false
    var isResolvingConflict = false

    private let coordinator: AppCoordinator
    private var autosaveTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var currentRouteURL: URL?
    private var editGeneration = 0
    private var saveInFlight = false
    private var queuedSaveGeneration: Int?
    private var visibleEditorURLs: Set<URL> = []

    init(
        session: AppSession,
        coordinator: AppCoordinator,
        autosaveDelay: Duration = .milliseconds(750)
    ) {
        self.session = session
        self.coordinator = coordinator
        self.autosaveDelay = autosaveDelay
    }

    var document: OpenDocument? {
        session.openDocument
    }

    var currentRouteDocument: OpenDocument? {
        guard session.openDocument?.url == activeEditorURL else {
            return nil
        }

        return session.openDocument
    }

    var loadError: UserFacingError? {
        session.editorLoadError
    }

    var title: String {
        currentRouteDocument?.displayName ?? activeEditorURL?.lastPathComponent ?? "Editor"
    }

    var textBinding: Binding<String> {
        Binding(
            get: { self.currentRouteDocument?.text ?? "" },
            set: { newValue in
                self.handleTextChange(newValue)
            }
        )
    }

    var saveStateText: String {
        saveFailure?.title ?? "Save Failed"
    }

    var isDirty: Bool {
        currentRouteDocument?.isDirty ?? false
    }

    var showsUnsavedIndicator: Bool {
        currentRouteDocument?.saveState.showsUnsavedIndicator ?? false || isDirty
    }

    var saveFailure: UserFacingError? {
        guard case let .failed(error)? = currentRouteDocument?.saveState else {
            return nil
        }

        return error
    }

    var activeConflict: DocumentConflict? {
        currentRouteDocument?.conflictState.activeConflict
    }

    var conflictError: UserFacingError? {
        activeConflict?.error
    }

    var showsConflictResolveAction: Bool {
        activeConflict != nil
    }

    var showsSaveStatusIndicator: Bool {
        saveFailure != nil
    }

    var saveStateSymbolName: String {
        "exclamationmark.triangle.fill"
    }

    func handleTextChange(_ text: String) {
        guard let currentRouteDocument else {
            return
        }

        guard currentRouteDocument.text != text else {
            return
        }

        editGeneration += 1
        coordinator.updateDocumentText(text)

        guard document?.conflictState.isConflicted == false else {
            return
        }

        scheduleAutosave(for: editGeneration)
    }

    func handleAppear(for documentURL: URL) {
        visibleEditorURLs.insert(documentURL)
        currentRouteURL = documentURL

        if session.openDocument?.url == documentURL {
            session.editorLoadError = nil
            return
        }

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        session.editorLoadError = nil

        loadTask = Task {
            let result = await coordinator.loadDocument(at: documentURL)
            guard Task.isCancelled == false else {
                return
            }

            guard generation == loadGeneration else {
                return
            }

            if case let .failure(error) = result {
                session.editorLoadError = error
            }
        }
    }

    func handleDisappear(for documentURL: URL) {
        visibleEditorURLs.remove(documentURL)

        if let activeConflict = session.openDocument?.url == documentURL
            ? session.openDocument?.conflictState.activeConflict
            : nil
        {
            session.lastError = activeConflict.error
            return
        }

        Task {
            await flushPendingSaveIfNeeded()
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            guard document?.isDirty == true || saveInFlight || autosaveTask != nil else {
                return
            }

            Task {
                await flushPendingSaveIfNeeded()
            }
        case .active:
            break
        @unknown default:
            break
        }
    }

    func presentConflictResolution() {
        guard activeConflict != nil else {
            return
        }

        isShowingConflictResolution = true
    }

    func preserveConflictEdits() {
        autosaveTask?.cancel()
        isShowingConflictResolution = false
        coordinator.preserveConflictEdits()
    }

    func reloadFromDisk() {
        guard let currentRouteDocument, isResolvingConflict == false else {
            return
        }

        autosaveTask?.cancel()
        isResolvingConflict = true
        Task {
            let result = await coordinator.reloadDocumentFromDisk(currentRouteDocument)
            isResolvingConflict = false

            switch result {
            case let .success(reloadedDocument):
                session.openDocument = reloadedDocument
                isShowingConflictResolution = false
            case .failure:
                isShowingConflictResolution = false
            }
        }
    }

    func overwriteDisk() {
        guard let currentRouteDocument, isResolvingConflict == false else {
            return
        }

        autosaveTask?.cancel()
        isResolvingConflict = true

        var pendingDocument = currentRouteDocument
        pendingDocument.saveState = .saving
        pendingDocument.conflictState = .none
        session.openDocument = pendingDocument

        Task {
            let result = await coordinator.saveDocument(
                pendingDocument,
                overwriteConflict: true
            )
            isResolvingConflict = false
            applySaveResult(
                result,
                for: pendingDocument,
                generation: editGeneration,
                triggerConflictResolutionOnConflict: false
            )
        }
    }

    private func scheduleAutosave(for generation: Int) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: autosaveDelay)
            await requestAutosave(for: generation)
        }
    }

    private func requestAutosave(for generation: Int) async {
        guard generation == editGeneration else {
            return
        }

        if saveInFlight {
            queuedSaveGeneration = generation
            return
        }

        await startSave(for: generation)
    }

    private func flushPendingSaveIfNeeded() async {
        autosaveTask?.cancel()
        if saveInFlight {
            queuedSaveGeneration = editGeneration
            return
        }

        await startSave(for: editGeneration)
    }

    private func startSave(for generation: Int) async {
        guard var currentDocument = document else {
            return
        }

        guard currentDocument.conflictState.isConflicted == false else {
            if hasVisibleEditor {
                isShowingConflictResolution = true
            } else {
                session.lastError = currentDocument.conflictState.activeConflict?.error
            }
            return
        }

        guard currentDocument.isDirty else {
            return
        }

        saveInFlight = true
        currentDocument.saveState = .saving
        session.openDocument = currentDocument
        let snapshot = currentDocument

        let result = await coordinator.saveDocument(snapshot)
        saveInFlight = false
        applySaveResult(
            result,
            for: snapshot,
            generation: generation,
            triggerConflictResolutionOnConflict: hasVisibleEditor
        )

        guard document?.conflictState.isConflicted == false else {
            queuedSaveGeneration = nil
            return
        }

        if let queuedSaveGeneration, queuedSaveGeneration > generation {
            self.queuedSaveGeneration = nil
            await startSave(for: queuedSaveGeneration)
        }
    }

    private func applySaveResult(
        _ result: Result<OpenDocument, UserFacingError>,
        for snapshot: OpenDocument,
        generation: Int,
        triggerConflictResolutionOnConflict: Bool
    ) {
        switch result {
        case let .success(savedDocument):
            guard
                generation == editGeneration,
                let currentDocument = session.openDocument,
                currentDocument.text == snapshot.text
            else {
                return
            }

            session.openDocument = savedDocument

            if savedDocument.conflictState.needsResolution {
                if triggerConflictResolutionOnConflict {
                    isShowingConflictResolution = true
                } else {
                    session.lastError = savedDocument.conflictState.activeConflict?.error
                }
                return
            }

            isShowingConflictResolution = false
        case let .failure(error):
            if
                generation == editGeneration,
                var currentDocument = session.openDocument,
                currentDocument.text == snapshot.text
            {
                currentDocument.saveState = .failed(error)
                currentDocument.isDirty = true
                if currentDocument.conflictState.needsResolution == false {
                    currentDocument.conflictState = .none
                }
                session.openDocument = currentDocument
            }

            isShowingConflictResolution = false
        }
    }

    private var hasVisibleEditor: Bool {
        visibleEditorURLs.isEmpty == false
    }

    private var activeEditorURL: URL? {
        session.path.last?.editorURL ?? currentRouteURL
    }
}
