import Observation
import SwiftUI

@MainActor
@Observable
/// Editor-facing state for load, autosave, conflict UI, undo/redo commands, and observation tasks.
/// Keep file truth in `AppCoordinator`/`PlainTextDocumentSession` and text rendering/layout in the
/// `MarkdownEditorTextView` bridge before adding more editor model logic.
final class EditorViewModel {
    private static let observationSuppressionInterval: Duration = .seconds(1)

    let session: AppSession
    let autosaveDelay: Duration
    var isShowingConflictResolution = false
    var isResolvingConflict = false
    private(set) var isEditorFocused = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoCommandToken = 0
    private(set) var redoCommandToken = 0
    private(set) var dismissKeyboardCommandToken = 0

    private let coordinator: AppCoordinator
    private let editorAppearanceStore: EditorAppearanceStore
    private let themeStore: ThemeStore
    private var autosaveTask: Task<Void, Never>?
    private var flushSaveTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var conflictResolutionTask: Task<Void, Never>?
    private var flushSaveTaskGeneration = 0
    private var loadGeneration = 0
    private var conflictResolutionGeneration = 0
    private var currentRouteURL: URL?
    private var editGeneration = 0
    private var saveInFlight = false
    private var queuedSaveRequest: PendingSaveRequest?
    private var visibleEditorURLs: Set<URL> = []
    private var documentObservationTask: Task<Void, Never>?
    private var observedDocumentIdentity: String?
    private var suppressObservationUntil: ContinuousClock.Instant?

    private struct PendingSaveRequest: Equatable {
        let generation: Int
        let documentIdentity: String
    }

    init(
        session: AppSession,
        coordinator: AppCoordinator,
        editorAppearanceStore: EditorAppearanceStore,
        themeStore: ThemeStore = ThemeStore(),
        autosaveDelay: Duration = .milliseconds(750)
    ) {
        self.session = session
        self.coordinator = coordinator
        self.editorAppearanceStore = editorAppearanceStore
        self.themeStore = themeStore
        self.autosaveDelay = autosaveDelay
    }

    var document: OpenDocument? {
        session.openDocument
    }

    /// Editor rendering is still single-document: a routed editor becomes editable only when it
    /// matches the one shared `AppSession.openDocument` slot for the app.
    var currentRouteDocument: OpenDocument? {
        guard let openDocument = session.openDocument else {
            return nil
        }

        if let activeEditorRelativePath,
           openDocument.relativePath == activeEditorRelativePath {
            return openDocument
        }

        guard openDocument.url == activeEditorURL else {
            return nil
        }

        return openDocument
    }

    var loadError: UserFacingError? {
        session.editorLoadError
    }

    var alertError: UserFacingError? {
        session.editorAlertError
    }

    var title: String {
        currentRouteDocument?.displayName ?? activeEditorURL?.lastPathComponent ?? "Editor"
    }

    var documentLocationText: String? {
        guard let currentRouteDocument else {
            return nil
        }

        let components = currentRouteDocument.relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else {
            return nil
        }

        return components.dropLast().joined(separator: "/")
    }

    var showsEmptyDocumentPlaceholder: Bool {
        currentRouteDocument?.text.isEmpty == true
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

    var saveFailureMessage: String? {
        saveFailure?.message
    }

    var editorFont: Font {
        editorAppearanceStore.editorFont
    }

    var editorUIFont: UIFont {
        editorAppearanceStore.editorUIFont
    }

    var markdownSyntaxMode: MarkdownSyntaxMode {
        editorAppearanceStore.markdownSyntaxMode
    }

    var effectiveShowLineNumbers: Bool {
        editorAppearanceStore.effectiveShowLineNumbers
    }

    var resolvedEditorTheme: ResolvedEditorTheme {
        editorAppearanceStore.resolvedTheme(using: themeStore)
    }

    func handleTextChange(_ text: String) {
        guard let currentRouteDocument else {
            return
        }

        editGeneration += 1
        coordinator.updateDocumentText(text)

        guard document?.conflictState.isConflicted == false else {
            return
        }

        scheduleAutosave(
            for: editGeneration,
            documentIdentity: documentObservationIdentity(for: currentRouteDocument)
        )
    }

    func handleAppear(for documentURL: URL) {
        visibleEditorURLs.insert(documentURL)
        currentRouteURL = documentURL

        if currentRouteDocument != nil {
            session.editorLoadError = nil
            session.editorAlertError = nil
            if let currentRouteDocument {
                startObservingDocumentChanges(for: currentRouteDocument)
            }
            return
        }

        cancelConflictResolutionTask()
        stopObservingDocumentChanges()
        invalidatePendingLoad()
        let generation = loadGeneration
        session.editorLoadError = nil
        session.editorAlertError = nil

        loadTask = Task {
            let result = await coordinator.loadDocument(at: documentURL)
            guard Task.isCancelled == false else {
                return
            }

            guard shouldApplyLoadResult(for: documentURL, generation: generation) else {
                return
            }

            switch result {
            case let .success(document):
                await coordinator.activateLoadedDocument(document)
                startObservingDocumentChanges(for: document)
            case let .failure(error):
                session.editorLoadError = error
            }
        }
    }

    func handleDisappear(for documentURL: URL) {
        visibleEditorURLs.remove(documentURL)
        handleEditorFocusChange(false)

        if currentRouteURL == documentURL {
            currentRouteURL = nil
            session.editorLoadError = nil
            session.editorAlertError = nil
            cancelConflictResolutionTask()
            invalidatePendingLoad()
            stopObservingDocumentChanges()
        } else if hasVisibleEditor == false {
            stopObservingDocumentChanges()
        }

        if let activeConflict = session.openDocument?.url == documentURL
            ? session.openDocument?.conflictState.activeConflict
            : nil
        {
            session.workspaceAlertError = activeConflict.error
            return
        }

        scheduleImmediateSaveFlush(for: documentURL)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            guard let document, document.isDirty || saveInFlight || autosaveTask != nil else {
                return
            }

            scheduleImmediateSaveFlush(for: document)
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
        flushSaveTask?.cancel()
        isShowingConflictResolution = false
        coordinator.preserveConflictEdits()
    }

    func dismissAlert() {
        session.editorAlertError = nil
    }

    func handleEditorFocusChange(_ isFocused: Bool) {
        isEditorFocused = isFocused
        if isFocused == false {
            canUndo = false
            canRedo = false
        }
    }

    func updateUndoRedoAvailability(canUndo: Bool, canRedo: Bool) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }

    func requestUndo() {
        guard canUndo else {
            return
        }

        undoCommandToken += 1
    }

    func requestRedo() {
        guard canRedo else {
            return
        }

        redoCommandToken += 1
    }

    func requestKeyboardDismiss() {
        dismissKeyboardCommandToken += 1
    }

    func reloadFromDisk() {
        guard let currentRouteDocument, isResolvingConflict == false else {
            return
        }

        autosaveTask?.cancel()
        flushSaveTask?.cancel()
        let generation = beginConflictResolutionTask()
        let documentSnapshot = currentRouteDocument
        conflictResolutionTask = Task {
            defer {
                finishConflictResolutionTaskIfCurrent(generation)
            }

            let result = await coordinator.reloadDocumentFromDisk(documentSnapshot)
            guard Task.isCancelled == false else {
                return
            }
            guard shouldApplyDocumentActionResult(for: documentSnapshot, generation: generation) else {
                return
            }

            switch result {
            case let .success(reloadedDocument):
                session.openDocument = reloadedDocument
                session.editorAlertError = nil
                isShowingConflictResolution = false
            case let .failure(error):
                session.editorAlertError = error
                isShowingConflictResolution = false
            }
        }
    }

    func overwriteDisk() {
        guard let currentRouteDocument, isResolvingConflict == false else {
            return
        }

        autosaveTask?.cancel()
        flushSaveTask?.cancel()
        let generation = beginConflictResolutionTask()

        var pendingDocument = currentRouteDocument
        pendingDocument.saveState = .saving
        pendingDocument.conflictState = .none
        session.openDocument = pendingDocument

        conflictResolutionTask = Task {
            defer {
                finishConflictResolutionTaskIfCurrent(generation)
            }

            let result = await coordinator.saveDocument(
                pendingDocument,
                overwriteConflict: true
            )
            guard Task.isCancelled == false else {
                return
            }
            guard shouldApplyDocumentActionResult(for: pendingDocument, generation: generation) else {
                return
            }

            applySaveResult(
                result,
                for: pendingDocument,
                generation: editGeneration,
                triggerConflictResolutionOnConflict: false
            )
        }
    }

    private func scheduleAutosave(for generation: Int, documentIdentity: String) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(for: autosaveDelay)
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }

            await requestAutosave(for: generation, matching: documentIdentity)
        }
    }

    private func requestAutosave(for generation: Int, matching documentIdentity: String) async {
        guard Task.isCancelled == false else {
            return
        }

        guard generation == editGeneration else {
            return
        }

        guard isCurrentDocumentIdentity(documentIdentity) else {
            return
        }

        if saveInFlight {
            queuedSaveRequest = PendingSaveRequest(
                generation: generation,
                documentIdentity: documentIdentity
            )
            return
        }

        await startSave(for: generation, matching: documentIdentity)
    }

    private func scheduleImmediateSaveFlush(for documentURL: URL) {
        guard let document = session.openDocument, document.url == documentURL else {
            return
        }

        scheduleImmediateSaveFlush(for: document)
    }

    /// Immediate save flushing is view-model-owned: disappearing/backgrounding views schedule it,
    /// and the captured document identity prevents a later route change from saving another file.
    private func scheduleImmediateSaveFlush(for document: OpenDocument) {
        let request = PendingSaveRequest(
            generation: editGeneration,
            documentIdentity: documentObservationIdentity(for: document)
        )
        autosaveTask?.cancel()

        if saveInFlight {
            queuedSaveRequest = request
            return
        }

        flushSaveTask?.cancel()
        flushSaveTaskGeneration += 1
        let taskGeneration = flushSaveTaskGeneration
        flushSaveTask = Task {
            defer {
                finishFlushSaveTaskIfCurrent(taskGeneration)
            }

            await flushPendingSaveIfNeeded(request)
        }
    }

    private func flushPendingSaveIfNeeded(_ request: PendingSaveRequest) async {
        guard Task.isCancelled == false else {
            return
        }

        guard isCurrentDocumentIdentity(request.documentIdentity) else {
            return
        }

        if saveInFlight {
            queuedSaveRequest = request
            return
        }

        await startSave(for: request.generation, matching: request.documentIdentity)
    }

    private func startSave(for generation: Int, matching documentIdentity: String) async {
        guard var currentDocument = document else {
            return
        }

        guard documentObservationIdentity(for: currentDocument) == documentIdentity else {
            return
        }

        guard currentDocument.conflictState.isConflicted == false else {
            if hasVisibleEditor {
                isShowingConflictResolution = true
            } else {
                session.workspaceAlertError = currentDocument.conflictState.activeConflict?.error
            }
            return
        }

        guard currentDocument.isDirty else {
            return
        }

        saveInFlight = true
        queuedSaveRequest = nil
        currentDocument.saveState = .saving
        session.openDocument = currentDocument
        let snapshot = currentDocument

        let result = await coordinator.saveDocument(snapshot)
        suppressObservationUntil = ContinuousClock.now + Self.observationSuppressionInterval
        saveInFlight = false
        applySaveResult(
            result,
            for: snapshot,
            generation: generation,
            triggerConflictResolutionOnConflict: hasVisibleEditor
        )

        guard document?.conflictState.isConflicted == false else {
            queuedSaveRequest = nil
            return
        }

        if let queuedSaveRequest,
           queuedSaveRequest.generation > generation,
           isCurrentDocumentIdentity(queuedSaveRequest.documentIdentity) {
            self.queuedSaveRequest = nil
            await startSave(
                for: queuedSaveRequest.generation,
                matching: queuedSaveRequest.documentIdentity
            )
        } else if queuedSaveRequest != nil {
            queuedSaveRequest = nil
        }
    }

    private func applySaveResult(
        _ result: Result<OpenDocument, UserFacingError>,
        for snapshot: OpenDocument,
        generation: Int,
        triggerConflictResolutionOnConflict: Bool
    ) {
        guard
            let currentDocument = session.openDocument,
            isSameLogicalDocument(currentDocument, snapshot)
        else {
            isShowingConflictResolution = false
            return
        }

        switch result {
        case let .success(acknowledgedDocument):
            let mergedDocument: OpenDocument
            if acknowledgedDocument.conflictState.isConflicted {
                mergedDocument = mergeConflictedSaveResult(
                    acknowledgedDocument,
                    into: currentDocument,
                    for: snapshot
                )
            } else {
                mergedDocument = mergeSuccessfulSaveAcknowledgement(
                    acknowledgedDocument,
                    into: currentDocument,
                    for: snapshot
                )
            }

            session.openDocument = mergedDocument

            if mergedDocument.conflictState.needsResolution {
                if triggerConflictResolutionOnConflict {
                    isShowingConflictResolution = true
                } else {
                    session.workspaceAlertError = mergedDocument.conflictState.activeConflict?.error
                }
                return
            }

            isShowingConflictResolution = false
        case let .failure(error):
            guard generation == editGeneration, currentDocument.text == snapshot.text else {
                isShowingConflictResolution = false
                return
            }

            var failedDocument = currentDocument
            failedDocument.saveState = .failed(error)
            failedDocument.isDirty = true
            if failedDocument.conflictState.needsResolution == false {
                failedDocument.conflictState = .none
            }
            session.openDocument = failedDocument

            isShowingConflictResolution = false
        }
    }

    /// Merges a confirmed save acknowledgement back into the editor while preserving newer in-memory edits.
    /// This keeps the last confirmed disk version current so later autosaves and foreground revalidation do
    /// not treat the app's own successful write as an external modification.
    private func mergeSuccessfulSaveAcknowledgement(
        _ savedDocument: OpenDocument,
        into currentDocument: OpenDocument,
        for snapshot: OpenDocument
    ) -> OpenDocument {
        var mergedDocument = currentDocument
        mergedDocument.url = savedDocument.url
        mergedDocument.relativePath = savedDocument.relativePath
        mergedDocument.displayName = savedDocument.displayName
        mergedDocument.loadedVersion = savedDocument.loadedVersion
        mergedDocument.conflictState = .none

        if currentDocument.text == snapshot.text {
            mergedDocument.text = savedDocument.text
            mergedDocument.isDirty = false
            mergedDocument.saveState = savedDocument.saveState
        } else {
            mergedDocument.isDirty = true
            mergedDocument.saveState = .unsaved
        }

        return mergedDocument
    }

    private func mergeConflictedSaveResult(
        _ conflictedDocument: OpenDocument,
        into currentDocument: OpenDocument,
        for snapshot: OpenDocument
    ) -> OpenDocument {
        guard currentDocument.text != snapshot.text else {
            return conflictedDocument
        }

        var mergedDocument = currentDocument
        mergedDocument.url = conflictedDocument.url
        mergedDocument.relativePath = conflictedDocument.relativePath
        mergedDocument.displayName = conflictedDocument.displayName
        mergedDocument.isDirty = true
        mergedDocument.saveState = .unsaved
        mergedDocument.conflictState = conflictedDocument.conflictState
        return mergedDocument
    }

    private func isSameLogicalDocument(
        _ lhs: OpenDocument,
        _ rhs: OpenDocument
    ) -> Bool {
        if lhs.url == rhs.url {
            return true
        }

        return lhs.workspaceRootURL == rhs.workspaceRootURL && lhs.relativePath == rhs.relativePath
    }

    private var hasVisibleEditor: Bool {
        visibleEditorURLs.isEmpty == false
    }

    private var activeEditorURL: URL? {
        session.visibleEditorURL ?? currentRouteURL
    }

    private var activeEditorRelativePath: String? {
        session.visibleEditorRelativePath
    }

    private func startObservingDocumentChanges(for document: OpenDocument) {
        let identity = documentObservationIdentity(for: document)
        guard observedDocumentIdentity != identity else {
            return
        }

        stopObservingDocumentChanges()
        observedDocumentIdentity = identity
        let observedDocument = document

        documentObservationTask = Task { [weak self] in
            guard let self else {
                return
            }

            let streamResult = await coordinator.observeDocumentChanges(for: observedDocument)
            guard Task.isCancelled == false else {
                return
            }

            guard case let .success(stream) = streamResult else {
                if case let .failure(error) = streamResult {
                    session.editorAlertError = error
                }
                return
            }

            session.editorAlertError = nil

            for await _ in stream {
                guard Task.isCancelled == false else {
                    break
                }

                guard self.hasVisibleEditor else {
                    continue
                }

                guard self.currentRouteDocument != nil else {
                    continue
                }

                guard self.saveInFlight == false else {
                    continue
                }

                guard self.currentRouteDocument?.isDirty != true else {
                    continue
                }

                if let suppressObservationUntil, ContinuousClock.now < suppressObservationUntil {
                    continue
                }

                let result = await coordinator.revalidateObservedDocument(matching: observedDocument)
                guard Task.isCancelled == false else {
                    break
                }

                guard let result else {
                    continue
                }

                switch result {
                case let .success(revalidatedDocument):
                    session.editorAlertError = nil
                    if revalidatedDocument.conflictState.needsResolution {
                        isShowingConflictResolution = true
                    }
                case let .failure(error):
                    session.editorAlertError = error
                }
            }
        }
    }

    private func stopObservingDocumentChanges() {
        documentObservationTask?.cancel()
        documentObservationTask = nil
        observedDocumentIdentity = nil
    }

    private func invalidatePendingLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
    }

    private func finishFlushSaveTaskIfCurrent(_ generation: Int) {
        guard generation == flushSaveTaskGeneration else {
            return
        }

        flushSaveTask = nil
    }

    private func beginConflictResolutionTask() -> Int {
        conflictResolutionTask?.cancel()
        conflictResolutionGeneration += 1
        isResolvingConflict = true
        return conflictResolutionGeneration
    }

    private func cancelConflictResolutionTask() {
        conflictResolutionTask?.cancel()
        conflictResolutionTask = nil
        conflictResolutionGeneration += 1
        isResolvingConflict = false
        isShowingConflictResolution = false
    }

    private func finishConflictResolutionTaskIfCurrent(_ generation: Int) {
        guard generation == conflictResolutionGeneration else {
            return
        }

        isResolvingConflict = false
        conflictResolutionTask = nil
    }

    private func shouldApplyLoadResult(
        for documentURL: URL,
        generation: Int
    ) -> Bool {
        guard generation == loadGeneration else {
            return false
        }

        guard currentRouteURL == documentURL else {
            return false
        }

        return visibleEditorURLs.contains(documentURL)
    }

    private func shouldApplyDocumentActionResult(
        for documentSnapshot: OpenDocument,
        generation: Int
    ) -> Bool {
        guard generation == conflictResolutionGeneration else {
            return false
        }

        guard let currentRouteDocument else {
            return false
        }

        return isSameLogicalDocument(currentRouteDocument, documentSnapshot)
    }

    private func documentObservationIdentity(for document: OpenDocument) -> String {
        "\(document.workspaceRootURL.path)|\(document.relativePath)"
    }

    private func isCurrentDocumentIdentity(_ identity: String) -> Bool {
        guard let document else {
            return false
        }

        return documentObservationIdentity(for: document) == identity
    }
}
