import CryptoKit
import Foundation

/// Coordinates live reads and writes for the active editor document against the real workspace file.
/// The current editor buffer is authoritative for autosave; coordinated reload/revalidation only
/// interrupts when the path disappears or a coordinated read/write fails unrecoverably.
actor PlainTextDocumentSession {
    /// Some provider-backed locations do not emit reliable `NSFilePresenter` callbacks.
    /// Treat fallback polling as degraded detection, not steady-state observation: only emit a
    /// synthetic change when cheap file metadata actually moves, and back off when repeated polls
    /// stay unchanged.
    struct ObservationFallbackSchedule: Sendable {
        let intervals: [Duration]

        init(intervals: [Duration]) {
            precondition(intervals.isEmpty == false, "Fallback schedule must contain at least one interval.")
            self.intervals = intervals
        }

        func interval(forUnchangedPollCount count: Int) -> Duration {
            intervals[min(max(count, 0), intervals.count - 1)]
        }

        static let live = ObservationFallbackSchedule(
            intervals: [.seconds(3), .seconds(6), .seconds(12), .seconds(24), .seconds(30)]
        )
    }

    /// Fallback polling is degraded mode:
    /// - `automatic`: only when presenter observation is unavailable or the file lives in a
    ///   provider-backed location where presenter callbacks are known to be weaker.
    /// - `always` / `never`: test and diagnostics overrides so the active mode is explicit.
    enum ObservationFallbackPolicy: Sendable {
        case automatic
        case always
        case never
    }

    enum ObservationMode: Equatable, Sendable {
        case filePresenterOnly
        case filePresenterWithFallbackPolling
        case fallbackPollingOnly
        case inactive
    }

    private let workspaceRootURL: URL
    private var relativePath: String
    private let securityScopedAccess: any SecurityScopedAccessHandling
    private let logger: DebugLogger?
    private let filePresenterEnabled: Bool
    private let observationFallbackPolicy: ObservationFallbackPolicy
    private let observationFallbackSchedule: ObservationFallbackSchedule
    private let onFallbackPoll: (@Sendable () -> Void)?
    private let onObservationModeActivated: (@Sendable (ObservationMode) -> Void)?
    private var observationLease: SecurityScopedAccessLease?
    private var observationURL: URL?
    private var filePresenter: PlainTextDocumentFilePresenter?
    private var observationFallbackTask: Task<Void, Never>?
    private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var lastFallbackSnapshot: ObservationFallbackSnapshot?
    private var unchangedFallbackPollCount = 0
    private var lastPublishedObservationMode: ObservationMode?

    init(
        relativePath: String,
        workspaceRootURL: URL,
        securityScopedAccess: any SecurityScopedAccessHandling,
        logger: DebugLogger? = nil,
        filePresenterEnabled: Bool = true,
        observationFallbackPolicy: ObservationFallbackPolicy = .automatic,
        observationFallbackSchedule: ObservationFallbackSchedule = .live,
        onFallbackPoll: (@Sendable () -> Void)? = nil,
        onObservationModeActivated: (@Sendable (ObservationMode) -> Void)? = nil
    ) {
        self.relativePath = relativePath
        self.workspaceRootURL = workspaceRootURL
        self.securityScopedAccess = securityScopedAccess
        self.logger = logger
        self.filePresenterEnabled = filePresenterEnabled
        self.observationFallbackPolicy = observationFallbackPolicy
        self.observationFallbackSchedule = observationFallbackSchedule
        self.onFallbackPoll = onFallbackPoll
        self.onObservationModeActivated = onObservationModeActivated
    }

    func openDocument(fallbackName: String) async throws -> OpenDocument {
        let relativePath = self.relativePath
        let workspaceRootURL = self.workspaceRootURL
        let securityScopedAccess = self.securityScopedAccess

        return try await Self.runStructuredBackgroundOperation(priority: .userInitiated) {
            try Task.checkCancellation()
            return try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                try Task.checkCancellation()
                switch Self.readDocumentState(at: securedURL) {
                case let .success(documentState):
                    return OpenDocument(
                        url: securedURL,
                        workspaceRootURL: workspaceRootURL,
                        relativePath: relativePath,
                        displayName: documentState.displayName,
                        text: documentState.text,
                        loadedVersion: documentState.version,
                        isDirty: false,
                        saveState: .idle,
                        conflictState: .none
                    )
                case .failure(.missing):
                    throw AppError.documentUnavailable(name: fallbackName)
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }
    }

    func reloadDocument(from document: OpenDocument) async throws -> OpenDocument {
        try await openDocument(fallbackName: document.displayName)
    }

    /// Starts live observation for the active file. The stream does not apply its own conflict policy;
    /// callers should feed events back through `revalidateDocument(_:)` so foreground refresh and
    /// live refresh always share the same calm external-change behavior.
    func observeChanges() async throws -> AsyncStream<Void> {
        try ensureObservationStarted()
        let identifier = UUID()

        return AsyncStream { continuation in
            changeContinuations[identifier] = continuation
            startFallbackObservationIfRequired()
            publishObservationModeIfNeeded()
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeChangeContinuation(for: identifier)
                }
            }
        }
    }

    /// Revalidates the active document without treating the editor's own coordinated saves as conflicts.
    /// Policy:
    /// - matching disk metadata: keep the current document as-is
    /// - disk now matches the current editor text: advance the confirmed disk version silently
    /// - clean buffer + safe external change: reload from disk silently
    /// - dirty buffer + external drift: keep the local buffer authoritative and avoid conflict UI
    /// - missing path: move into explicit recovery because the file can no longer be reconciled safely
    func revalidateDocument(_ document: OpenDocument) async throws -> OpenDocument {
        let relativePath = self.relativePath
        let workspaceRootURL = self.workspaceRootURL
        let securityScopedAccess = self.securityScopedAccess

        return try await Self.runStructuredBackgroundOperation(priority: .utility) {
            try Task.checkCancellation()
            return try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                try Task.checkCancellation()
                switch Self.readDocumentState(at: securedURL) {
                case let .success(diskDocument):
                    if document.loadedVersion.matchesCurrentDisk(diskDocument.version) {
                        var validatedDocument = document
                        validatedDocument.url = securedURL
                        validatedDocument.displayName = diskDocument.displayName
                        return validatedDocument
                    }

                    if diskDocument.text == document.text {
                        var updatedDocument = document
                        updatedDocument.url = securedURL
                        updatedDocument.displayName = diskDocument.displayName
                        updatedDocument.loadedVersion = diskDocument.version
                        updatedDocument.conflictState = .none
                        return updatedDocument
                    }

                    guard document.isDirty == false else {
                        var preservedDocument = document
                        preservedDocument.url = securedURL
                        preservedDocument.displayName = diskDocument.displayName
                        preservedDocument.conflictState = .none
                        return preservedDocument
                    }

                    return OpenDocument(
                        url: securedURL,
                        workspaceRootURL: workspaceRootURL,
                        relativePath: relativePath,
                        displayName: diskDocument.displayName,
                        text: diskDocument.text,
                        loadedVersion: diskDocument.version,
                        isDirty: false,
                        saveState: .idle,
                        conflictState: .none
                    )
                case .failure(.missing):
                    return Self.makeConflictDocument(
                        from: document,
                        kind: .missingOnDisk
                    )
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }
    }

    /// Performs a coordinated last-writer-wins save for the active editor buffer.
    ///
    /// Write strategy:
    /// - coordinate the live workspace URL with `NSFileCoordinator`
    /// - write the UTF-8 buffer directly to that coordinated URL
    /// - do not add a second temp-file replacement step on top
    ///
    /// This is intentional for provider-backed folders. The app edits the user-selected workspace in place,
    /// and adding another replacement hop can trigger exactly the extra provider churn and file-identity noise
    /// that this live document session is meant to avoid. The tradeoff is that durability still depends on the
    /// underlying provider honoring the coordinated direct write, so real-device QA on iCloud/Files providers
    /// remains part of the product contract.
    ///
    /// The active buffer remains authoritative during ordinary typing; only missing paths or unrecoverable
    /// write failures interrupt it.
    func saveDocument(
        _ document: OpenDocument,
        overwriteConflict: Bool
    ) async throws -> OpenDocument {
        let relativePath = self.relativePath
        let workspaceRootURL = self.workspaceRootURL
        let securityScopedAccess = self.securityScopedAccess

        return try await Self.runDetachedWriteOperation(priority: .utility) {
            try securityScopedAccess.withAccess(
                toDescendantAt: relativePath,
                within: workspaceRootURL
            ) { securedURL in
                if overwriteConflict == false {
                    switch Self.readPresenceState(at: securedURL, fallbackName: document.displayName) {
                    case .success:
                        break
                    case .failure(.missing):
                        return Self.makeConflictDocument(
                            from: document,
                            kind: .missingOnDisk
                        )
                    case let .failure(.appError(error)):
                        throw error
                    }
                }

                switch Self.writeDocumentState(
                    text: document.text,
                    to: securedURL,
                    fallbackName: document.displayName
                ) {
                case let .success(savedState):
                    var savedDocument = document
                    savedDocument.url = securedURL
                    savedDocument.displayName = savedState.displayName
                    savedDocument.loadedVersion = savedState.version
                    savedDocument.isDirty = false
                    savedDocument.saveState = .saved(Date())
                    savedDocument.conflictState = .none
                    return savedDocument
                case .failure(.missing):
                    return Self.makeConflictDocument(
                        from: document,
                        kind: .missingOnDisk
                    )
                case let .failure(.appError(error)):
                    throw error
                }
            }
        }
    }

    /// Retargets the active document session after an in-app coordinated rename so subsequent saves,
    /// reloads, and presenter callbacks continue following the moved file.
    func relocate(to url: URL, relativePath: String) {
        self.relativePath = relativePath
        observationURL = url
        filePresenter?.updatePresentedItemURL(to: url)
        resetObservationFallbackState()
    }

    private func ensureObservationStarted() throws {
        guard observationLease == nil else {
            return
        }

        let lease = try securityScopedAccess.beginAccess(to: workspaceRootURL)
        guard let observedURL = WorkspaceRelativePath.resolveExisting(
            relativePath,
            within: lease.url
        ) else {
            lease.endAccess()
            throw AppError.documentUnavailable(
                name: Self.descendantDisplayName(for: relativePath)
            )
        }

        observationLease = lease
        observationURL = observedURL

        // File-presenter callbacks are the primary observation path. Metadata polling stays
        // degraded mode and only starts later if the session policy says presenter callbacks are
        // unavailable or the observed location looks provider-backed enough to justify fallback.
        guard filePresenterEnabled else {
            return
        }

        let presenter = PlainTextDocumentFilePresenter(
            url: observedURL,
            onChange: { [weak self] in
                Task {
                    await self?.emitObservedChange()
                }
            }
        )

        NSFileCoordinator.addFilePresenter(presenter)
        filePresenter = presenter
    }

    private func emitObservedChange() {
        guard changeContinuations.isEmpty == false else {
            return
        }

        for continuation in changeContinuations.values {
            continuation.yield(())
        }
    }

    private func removeChangeContinuation(for identifier: UUID) {
        changeContinuations.removeValue(forKey: identifier)
        guard changeContinuations.isEmpty else {
            return
        }

        observationFallbackTask?.cancel()
        observationFallbackTask = nil

        if let filePresenter {
            NSFileCoordinator.removeFilePresenter(filePresenter)
            self.filePresenter = nil
        }

        observationURL = nil
        observationLease?.endAccess()
        observationLease = nil
        lastPublishedObservationMode = nil
        resetObservationFallbackState()
    }

    private func startFallbackObservationIfRequired() {
        guard changeContinuations.isEmpty == false else {
            return
        }

        guard shouldActivateFallbackObservation() else {
            return
        }

        startObservationFallbackIfNeeded()
    }

    /// Normal editors stay on presenter callbacks alone. Fallback polling becomes active only when
    /// the presenter path is unavailable or the policy marks the current location as provider-backed
    /// degraded mode.
    private func shouldActivateFallbackObservation() -> Bool {
        switch observationFallbackPolicy {
        case .automatic:
            guard filePresenterEnabled else {
                return true
            }

            guard let observationURL else {
                return false
            }

            return Self.locationNeedsFallbackObservation(at: observationURL)
        case .always:
            return true
        case .never:
            return false
        }
    }

    private func startObservationFallbackIfNeeded() {
        guard observationFallbackTask == nil else {
            return
        }

        let fallbackSchedule = observationFallbackSchedule
        observationFallbackTask = Task { [weak self] in
            await self?.primeObservationFallbackState()

            while Task.isCancelled == false {
                let interval = await self?.currentObservationFallbackInterval()
                    ?? fallbackSchedule.interval(forUnchangedPollCount: 0)
                try? await Task.sleep(for: interval)
                guard Task.isCancelled == false else {
                    break
                }

                await self?.performObservationFallbackPoll()
            }
        }
    }

    private func primeObservationFallbackState() {
        lastFallbackSnapshot = loadObservationFallbackSnapshot()
        unchangedFallbackPollCount = 0
    }

    private func currentObservationFallbackInterval() -> Duration {
        observationFallbackSchedule.interval(forUnchangedPollCount: unchangedFallbackPollCount)
    }

    private func performObservationFallbackPoll() {
        onFallbackPoll?()

        let snapshot = loadObservationFallbackSnapshot()
        guard snapshot != lastFallbackSnapshot else {
            unchangedFallbackPollCount += 1
            return
        }

        lastFallbackSnapshot = snapshot
        unchangedFallbackPollCount = 0
        emitObservedChange()
    }

    private func resetObservationFallbackState() {
        lastFallbackSnapshot = nil
        unchangedFallbackPollCount = 0
    }

    private func publishObservationModeIfNeeded() {
        let mode = currentObservationMode()
        guard mode != lastPublishedObservationMode else {
            return
        }

        lastPublishedObservationMode = mode
        onObservationModeActivated?(mode)

        guard let observationURL else {
            logger?.log(category: "Document", "Observation mode: \(mode.description).")
            return
        }

        let displayPath = WorkspaceRelativePath.make(for: observationURL, within: workspaceRootURL)
            ?? observationURL.lastPathComponent
        logger?.log(
            category: "Document",
            "Observing \(displayPath) via \(mode.description)."
        )
    }

    private func currentObservationMode() -> ObservationMode {
        let filePresenterActive = filePresenter != nil
        let fallbackActive = observationFallbackTask != nil

        switch (filePresenterActive, fallbackActive) {
        case (true, true):
            return ObservationMode.filePresenterWithFallbackPolling
        case (true, false):
            return ObservationMode.filePresenterOnly
        case (false, true):
            return ObservationMode.fallbackPollingOnly
        case (false, false):
            return ObservationMode.inactive
        }
    }

    private func loadObservationFallbackSnapshot() -> ObservationFallbackSnapshot? {
        guard let observationURL else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: observationURL.path)
            guard (attributes[.type] as? FileAttributeType) != .typeDirectory else {
                return .missing
            }

            return .existing(
                contentModificationDate: attributes[.modificationDate] as? Date,
                fileSize: (attributes[.size] as? NSNumber)?.intValue ?? 0
            )
        } catch {
            if Self.isMissingFileError(error) {
                return .missing
            }

            return .unreadable
        }
    }

    nonisolated static func makeConflictDocument(
        from document: OpenDocument,
        kind: DocumentConflict.Kind
    ) -> OpenDocument {
        let userFacingError = switch kind {
        case .modifiedOnDisk:
            UserFacingError(
                title: "File Changed Elsewhere",
                message: "\(document.displayName) changed on disk after it was opened.",
                recoverySuggestion: "Reload from disk, replace the file with your current text, or keep your edits in memory for now."
            )
        case .missingOnDisk:
            UserFacingError(
                title: "File No Longer Exists",
                message: "\(document.displayName) was moved or deleted outside the app.",
                recoverySuggestion: "Reload if it returns, replace it at this path, or keep your edits in memory for now."
            )
        }

        var conflictedDocument = document
        conflictedDocument.isDirty = document.isDirty
        conflictedDocument.saveState = document.isDirty ? .unsaved : .idle
        conflictedDocument.conflictState = .needsResolution(
            DocumentConflict(kind: kind, error: userFacingError)
        )
        return conflictedDocument
    }

    nonisolated private static func readDocumentState(
        at url: URL
    ) -> Result<CoordinatedDocumentState, AppErrorOrMissing> {
        var coordinationError: NSError?
        var result: Result<CoordinatedDocumentState, AppErrorOrMissing>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = loadDocumentState(at: coordinatedURL)
        }

        if let coordinationError {
            return wrapFilesystemError(
                coordinationError,
                name: url.lastPathComponent,
                makeAppError: { name in
                    AppError.documentOpenFailed(
                        name: name,
                        details: "The file could not be read from disk."
                    )
                }
            )
        }

        return result ?? .failure(
            .appError(
                AppError.documentOpenFailed(
                    name: url.lastPathComponent,
                    details: "The coordinated read did not return any data."
                )
            )
        )
    }

    nonisolated private static func readPresenceState(
        at url: URL,
        fallbackName: String
    ) -> Result<CoordinatedPresenceState, AppErrorOrMissing> {
        var coordinationError: NSError?
        var result: Result<CoordinatedPresenceState, AppErrorOrMissing>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = loadPresenceState(at: coordinatedURL, fallbackName: fallbackName)
        }

        if let coordinationError {
            return wrapFilesystemError(
                coordinationError,
                name: fallbackName,
                makeAppError: { name in
                    AppError.documentSaveFailed(
                        name: name,
                        details: "The current file metadata could not be read before saving."
                    )
                }
            )
        }

        return result ?? .failure(
            .appError(
                AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The file could not be checked before saving."
                )
            )
        )
    }

    nonisolated private static func writeDocumentState(
        text: String,
        to url: URL,
        fallbackName: String
    ) -> Result<CoordinatedDocumentState, AppErrorOrMissing> {
        var coordinationError: NSError?
        var result: Result<CoordinatedDocumentState, AppErrorOrMissing>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let parentURL = coordinatedURL.deletingLastPathComponent()
                let parentValues = try parentURL.resourceValues(forKeys: [.isDirectoryKey])
                guard parentValues.isDirectory == true else {
                    result = .failure(.missing)
                    return
                }

                // Intentionally write straight through the coordinated URL. We avoid layering another
                // temp-file replace on top because provider-backed folders are calmer when the app keeps
                // one coordinated in-place write boundary instead of manufacturing an extra replacement step.
                try writeUTF8Text(text, to: coordinatedURL, fallbackName: fallbackName)

                let resourceValues = try coordinatedURL.resourceValues(forKeys: documentResourceKeys)
                guard resourceValues.isDirectory != true else {
                    throw AppError.documentSaveFailed(
                        name: fallbackName,
                        details: "The path now points to a folder instead of a file."
                    )
                }

                result = .success(
                    CoordinatedDocumentState(
                        displayName: resourceValues.localizedName ?? resourceValues.name ?? coordinatedURL.lastPathComponent,
                        text: text,
                        version: makeLoadedVersion(from: resourceValues, text: text)
                    )
                )
            } catch let error as AppError {
                result = .failure(.appError(error))
            } catch {
                result = wrapFilesystemError(
                    error,
                    name: fallbackName,
                    makeAppError: { name in
                        AppError.documentSaveFailed(
                            name: name,
                            details: "The latest text could not be written to disk."
                        )
                    }
                )
            }
        }

        if let coordinationError {
            return wrapFilesystemError(
                coordinationError,
                name: fallbackName,
                makeAppError: { name in
                    AppError.documentSaveFailed(
                        name: name,
                        details: "The coordinated write could not be completed."
                    )
                }
            )
        }

        return result ?? .failure(
            .appError(
                AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The coordinated write did not return a saved state."
                )
            )
        )
    }

    nonisolated private static func loadDocumentState(
        at url: URL
    ) -> Result<CoordinatedDocumentState, AppErrorOrMissing> {
        do {
            let resourceValues = try url.resourceValues(forKeys: documentResourceKeys)
            guard resourceValues.isDirectory != true else {
                throw AppError.documentOpenFailed(
                    name: url.lastPathComponent,
                    details: "The selected path is not a plain text file."
                )
            }

            let text = try readUTF8Text(from: url)

            return .success(
                CoordinatedDocumentState(
                    displayName: resourceValues.localizedName ?? resourceValues.name ?? url.lastPathComponent,
                    text: text,
                    version: makeLoadedVersion(from: resourceValues, text: text)
                )
            )
        } catch let error as AppError {
            return .failure(.appError(error))
        } catch {
            return wrapFilesystemError(
                error,
                name: url.lastPathComponent,
                makeAppError: { name in
                    AppError.documentOpenFailed(
                        name: name,
                        details: "The file could not be read from disk."
                    )
                }
            )
        }
    }

    nonisolated private static func loadPresenceState(
        at url: URL,
        fallbackName: String
    ) -> Result<CoordinatedPresenceState, AppErrorOrMissing> {
        do {
            let resourceValues = try url.resourceValues(forKeys: documentResourceKeys)
            guard resourceValues.isDirectory != true else {
                throw AppError.documentSaveFailed(
                    name: fallbackName,
                    details: "The path now points to a folder instead of a file."
                )
            }

            return .success(
                CoordinatedPresenceState(
                    displayName: resourceValues.localizedName ?? resourceValues.name ?? fallbackName
                )
            )
        } catch let error as AppError {
            return .failure(.appError(error))
        } catch {
            return wrapFilesystemError(
                error,
                name: fallbackName,
                makeAppError: { name in
                    AppError.documentSaveFailed(
                        name: name,
                        details: "The current file metadata could not be read before saving."
                    )
                }
            )
        }
    }

    nonisolated private static func makeLoadedVersion(
        from resourceValues: URLResourceValues,
        text: String
    ) -> DocumentVersion {
        let data = Data(text.utf8)
        return DocumentVersion(
            contentModificationDate: resourceValues.contentModificationDate,
            fileSize: resourceValues.fileSize ?? data.count,
            contentDigest: SHA256.hash(data: data).compactMap { byte in
                String(format: "%02x", byte)
            }.joined()
        )
    }

    /// The editor treats workspace files as strict UTF-8 plain text. It does not normalize line endings;
    /// whatever line breaks are present in the in-memory buffer are written back as-is.
    nonisolated private static func readUTF8Text(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.documentOpenFailed(
                name: url.lastPathComponent,
                details: "The file is not valid UTF-8 text."
            )
        }

        return text
    }

    /// Encodes the current editor buffer directly as UTF-8 without rewriting line endings.
    nonisolated private static func writeUTF8Text(
        _ text: String,
        to url: URL,
        fallbackName: String
    ) throws {
        guard let data = text.data(using: .utf8) else {
            throw AppError.documentSaveFailed(
                name: fallbackName,
                details: "The current text could not be encoded as UTF-8."
            )
        }

        try data.write(to: url, options: [])
    }

    nonisolated private static func wrapFilesystemError<Success>(
        _ error: Error,
        name: String,
        makeAppError: (String) -> AppError
    ) -> Result<Success, AppErrorOrMissing> {
        if isMissingFileError(error) {
            return .failure(.missing)
        }

        return .failure(.appError(makeAppError(name)))
    }

    nonisolated private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return true
        }

        if nsError.domain == NSPOSIXErrorDomain, nsError.code == ENOENT {
            return true
        }

        return false
    }

    nonisolated private static var documentResourceKeys: Set<URLResourceKey> {
        [
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedNameKey,
            .nameKey,
            .isDirectoryKey,
        ]
    }

    nonisolated private static func descendantDisplayName(for relativePath: String) -> String {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? "Document"
    }

    /// Treat ubiquitous or non-local volumes as provider-backed locations where presenter callbacks
    /// are less trustworthy, so metadata polling stays available as degraded observation.
    nonisolated private static func locationNeedsFallbackObservation(at url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(
                forKeys: [
                    .isUbiquitousItemKey,
                    .volumeIsLocalKey,
                ]
            )

            if resourceValues.isUbiquitousItem == true {
                return true
            }

            if resourceValues.volumeIsLocal == false {
                return true
            }
        } catch {
            return false
        }

        return false
    }

    /// Keeps expensive read/revalidate work off the actor's serial executor without discarding
    /// parent-task cancellation the way `Task.detached` would.
    nonisolated private static func runStructuredBackgroundOperation<Value: Sendable>(
        priority: TaskPriority,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(priority: priority) {
                try Task.checkCancellation()
                let value = try operation()
                try Task.checkCancellation()
                return value
            }

            defer {
                group.cancelAll()
            }

            guard let value = try await group.next() else {
                throw CancellationError()
            }

            return value
        }
    }

    /// Save is intentionally detached from caller cancellation once it has started coordinating a
    /// write. Save requests come from transient UI/autosave tasks, but an in-flight write should
    /// finish and report a real outcome instead of being interrupted purely because the caller task
    /// was canceled after the save already began.
    nonisolated private static func runDetachedWriteOperation<Value: Sendable>(
        priority: TaskPriority,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: priority) {
            try operation()
        }.value
    }
}

private extension PlainTextDocumentSession.ObservationMode {
    nonisolated var description: String {
        switch self {
        case .filePresenterOnly:
            "primary file presenter"
        case .filePresenterWithFallbackPolling:
            "primary file presenter + degraded fallback polling"
        case .fallbackPollingOnly:
            "degraded fallback polling only"
        case .inactive:
            "no active observation"
        }
    }
}

private enum ObservationFallbackSnapshot: Equatable {
    case existing(contentModificationDate: Date?, fileSize: Int)
    case missing
    case unreadable
}

private struct CoordinatedDocumentState: Sendable {
    let displayName: String
    let text: String
    let version: DocumentVersion
}

private struct CoordinatedPresenceState: Sendable {
    let displayName: String
}

private enum AppErrorOrMissing: Error, Sendable {
    case appError(AppError)
    case missing
}

private final class PlainTextDocumentFilePresenter: NSObject, NSFilePresenter {
    nonisolated var presentedItemURL: URL? {
        urlLock.lock()
        defer { urlLock.unlock() }
        return currentPresentedItemURL
    }
    nonisolated let presentedItemOperationQueue: OperationQueue

    nonisolated private let onChange: @Sendable () -> Void
    private let urlLock = NSLock()
    nonisolated(unsafe) private var currentPresentedItemURL: URL?

    nonisolated init(
        url: URL,
        onChange: @escaping @Sendable () -> Void
    ) {
        currentPresentedItemURL = url
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.qualityOfService = .utility
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        self.onChange = onChange
    }

    nonisolated func presentedItemDidChange() {
        onChange()
    }

    nonisolated func presentedItemDidMove(to newURL: URL) {
        updatePresentedItemURL(to: newURL)
        onChange()
    }

    nonisolated func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onChange()
        completionHandler(nil)
    }

    nonisolated func updatePresentedItemURL(to url: URL) {
        urlLock.lock()
        currentPresentedItemURL = url
        urlLock.unlock()
    }
}
