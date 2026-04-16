# CODE_REVIEW.md

## Scope

This review covered the full repository layout, the core app/session/coordinator flow, workspace and document persistence boundaries, editor and workspace view models, and the existing unit/smoke tests.

I **did not execute the Xcode test suite** because this environment does not include `xcodebuild`. The conclusions below come from static code review plus test-suite inspection.

## Overall assessment

Downward has a strong base:

- the architecture is easy to follow
- the save-ack merge logic is thoughtful
- the test suite is much better than average for a SwiftUI app in this size range
- the product docs are clear about the “calm editor” goal

That said, I would not treat the current build as fully hardened yet. The biggest remaining issues are not cosmetic; they sit on the trust boundary around file access, file identity, and long-lived observation.

## What is working well

### 1. The core split is sensible

`AppCoordinator`, `WorkspaceManager`, `DocumentManager`, and the view models each own a coherent slice of behavior. That separation makes the code reviewable and gives future changes real seams.

### 2. The autosave merge model is better than most MVP editors

`EditorViewModel` preserves newer in-memory edits when older save acknowledgements come back. That is exactly the right instinct for editor trust.

### 3. The tests are aimed at the right risks

The suite covers restore, revalidation, rename/delete coherence, and async race cases. That is where many file-based apps fall apart.

### 4. The project already resists some stale-result races

There are generation guards around document loading and workspace transitions. The remaining race problems are fixable because the code already uses the right pattern in several places.

---

## Findings

## P0 — Security-scoped bookmark creation and resolution are almost certainly wrong

### Evidence

`LiveSecurityScopedAccessHandler.makeBookmark(for:)` creates bookmark data with `options: []`.

`LiveSecurityScopedAccessHandler.resolveBookmark(_:)` resolves bookmark data with `options: []`.

### Why it matters

This is the app’s most important persistence boundary. If the bookmark is not created and resolved as a **security-scoped** bookmark, workspace restore can become flaky across relaunches or across providers even if same-session access appears to work.

### Why I ranked it P0

The whole product promise starts with “choose a folder once, restore it later.” If that boundary is shaky, everything above it is shaky.

### Recommendation

- Create the bookmark with security-scope options.
- Resolve it with security-scope options.
- Keep start/stop access explicit and centralized.
- Add a small test seam so bookmark creation and resolution options can be asserted without needing a real device.

### Suggested tests

- unit test around the bookmark adapter that verifies the expected creation and resolution options
- real-device QA pass for iCloud Drive and at least one provider-backed folder

---

## P1 — Path identity is inconsistent: some code uses real relative paths, some uses display names

### Evidence

- `OpenDocument.relativePath` comes from actual URL path components.
- `RecentFilesStore.pruneInvalidItems(using:)` rebuilds valid relative paths from `WorkspaceNode.displayName`.
- `WorkspaceSearchEngine` also builds user-visible relative paths from `displayName`.

### Why it matters

`displayName` is presentation data. It is not guaranteed to be a stable canonical identity. Once the code mixes “real path” and “display path,” persistence features can go wrong in subtle ways.

The clearest risk is recent-file pruning: a valid recent item can be dropped because the rebuilt path uses display names while the stored item uses the actual relative path.

### Recommendation

- Add a canonical `relativePath` to the snapshot tree or an equivalent identity type.
- Treat `displayName` as UI-only.
- Make recent files, restore, mutation reconciliation, and search all share the same canonical path identity.

### Suggested tests

- recent-file prune should survive when display names differ from the filesystem name
- rename/reconnect should preserve recent items using canonical relative paths only

---

## P1 — Editor load cancellation and observation lifecycle have a hole

### Evidence

`EditorViewModel.handleDisappear(for:)` does **not** cancel `loadTask` and does not invalidate `loadGeneration`.

`EditorViewModel.handleAppear(for:)` starts a document load and, on success, always calls `activateLoadedDocument` and `startObservingDocumentChanges(for:)`.

`startObservingDocumentChanges(for:)` does not require a visible editor before starting observation.

### Why it matters

If the user opens a document and backs out before the async load completes:

- the late load can still become the active `openDocument`
- the last-open session can still be updated
- document observation can start even though no editor is visible

That creates a “resurrected editor” problem and can also leave file presenters / fallback polling alive longer than intended.

### Recommendation

- cancel `loadTask` in `handleDisappear`
- bump or invalidate the generation when the route goes away
- only activate/start observing if the same document is still visible and still current

### Suggested tests

- open a file, navigate back immediately, then let the delayed load complete
- assert no active document is installed and no observation starts

---

## P1 — Workspace mutations use a different consistency model than document I/O

### Evidence

`LiveWorkspaceManager.createFile`, `renameFile`, and `deleteFile` use direct `Data.write`, `FileManager.moveItem`, and `FileManager.removeItem`.

The live document pipeline, by contrast, uses `NSFileCoordinator` for open/reload/revalidate/save.

### Why it matters

The app’s highest-risk operations should not have two different coordination models.

Right now:

- document I/O is coordinated
- browser mutations are not

That mismatch is risky for provider-backed folders and makes rename/move semantics less predictable for the live editor and file presenters.

### Recommendation

Create a single coordinated mutation boundary for create/rename/delete so browser mutations and editor I/O follow the same rules.

### Suggested tests

- rename/delete of an active open file through the browser while observation is live
- provider-backed mutation QA on device

---

## P1 — Refresh generation protection does not fully propagate to callers

### Evidence

`LiveWorkspaceManager.loadSnapshot` uses `refreshGeneration` only to decide whether to update `currentSnapshot`. It still returns the snapshot to the caller even if the result is stale.

`AppCoordinator.refreshWorkspace()` and `handleSceneDidBecomeActive()` apply whatever snapshot they receive.

### Why it matters

Two overlapping refreshes can still race at the coordinator/session layer even if the manager protects only its own private cache.

### Recommendation

Move generation ownership higher:

- either the manager should not return stale results
- or the coordinator should refuse to apply them

### Suggested tests

- delayed enumerator with two overlapping refresh requests
- assert the oldest result cannot overwrite the newest session state

---

## P2 — Document writes are intentionally non-atomic, which is a trust tradeoff that is not yet explicitly owned

### Evidence

`PlainTextDocumentSession.writeDocumentState(...)` writes directly to the coordinated URL with `Data.write(..., options: [])`.

The comment explicitly avoids another atomic replacement step.

### Why it matters

This may reduce provider churn, but it also lowers write durability. For a file editor, “the save path cannot corrupt the file” is one of the hardest trust requirements.

### Recommendation

Do not leave this as an implicit tradeoff.

Pick and document one of these strategies:

1. provider-friendly direct writes plus extra corruption detection / retry logic, or
2. safer temp-write-and-replace where the provider behavior is acceptable

Either choice is defensible; the current issue is that the durability decision is present in code but not yet treated as an explicit product/architecture decision.

---

## P2 — The fallback observation loop causes ongoing revalidation churn

### Evidence

`PlainTextDocumentSession.startObservationFallbackIfNeeded()` emits a change every 3 seconds even when nothing changed.

`EditorViewModel.startObservingDocumentChanges(for:)` revalidates on every emitted event whenever the document is clean and visible.

### Why it matters

That means a clean visible editor can perform coordinated reads forever with no actual change signal. This is exactly the kind of quiet provider churn that becomes visible on real devices as battery use, sluggishness, or noisy logs.

### Recommendation

- treat the fallback as a degraded mode, not the default steady state
- add metadata gating, backoff, or a “presenter appears inactive” heuristic
- keep the fallback cheap when the file is stable

### Suggested tests

- no-change observation should not repeatedly revalidate forever in a tight cadence

---

## P2 — Workspace enumeration is fail-fast and may be too eager for real folders

### Evidence

`LiveWorkspaceEnumerator.makeNodes(in:)` recursively walks every child and throws on any nested failure.

### Why it matters

One unreadable child folder can fail the whole workspace refresh. Also, deeply nested metadata or provider-generated folders can make refresh slower than necessary.

### Recommendation

- decide an explicit policy for hidden / package / metadata-like folders
- continue past unreadable children where possible
- log skipped nodes instead of failing the whole snapshot unless the root itself is unreadable

### Suggested tests

- unreadable nested folder fixture
- large hidden subtree fixture
- partial snapshot should still load the rest of the workspace

---

## P3 — Case-only rename is fragile on case-insensitive providers

### Evidence

`renameFile(at:to:)` checks `fileExists(atPath:)` before moving. On a case-insensitive provider, `foo.md -> Foo.md` can look like a duplicate even though it is meant to be the same file renamed by case only.

### Recommendation

Handle the “same item, different case” path explicitly.

### Suggested tests

- case-only rename fixture in a case-insensitive test harness or provider-aware integration test

---

## P3 — There is some dormant or mismatched state in the model layer

### Evidence

- `WorkspaceAccessState.restorable` appears unused by the live app flow.
- `DocumentConflict.Kind.modifiedOnDisk` is not produced by the live document pipeline.
- `AppCoordinator.present(_ error:context:)` appears unused.

### Why it matters

This is not a release blocker, but dead states make it harder to understand what the shipping behavior actually is.

### Recommendation

Remove or wire up these cases and align docs with the behavior you actually intend to ship.

---

## Test-suite assessment

The existing suite is a real asset. I would keep it and expand it before any more feature work.

### Strong coverage already present

- save-ack merge behavior
- foreground revalidation behavior
- restore/reconnect flows
- rename/delete coherence
- search and recent-files basics

### Most important missing tests

1. delayed editor load followed by route disappearance
2. overlapping workspace refreshes
3. display-name vs canonical-path divergence
4. case-only rename
5. unreadable nested folder during snapshot build
6. observation fallback does not churn indefinitely when nothing changed
7. workspace mutation coordination behavior on provider-backed folders

---

## Recommended execution order

1. Fix the security-scoped bookmark boundary.
2. Unify canonical relative-path identity across snapshot, recents, restore, and search.
3. Fix editor-load cancellation and observation start/stop rules.
4. Move create/rename/delete onto a coordinated mutation path.
5. Add end-to-end refresh generation protection.
6. Decide and document the write-durability strategy.
7. Reduce fallback polling churn.
8. Make enumeration resilient and define skip policy.
9. Clean out dormant states and doc drift.

## Bottom line

This repo is in good shape structurally. The remaining work is mostly **trust hardening**, not a rewrite.

That is good news: the app does not need a new architecture. It needs a tighter contract around the file boundary and a few carefully targeted state-management fixes.
