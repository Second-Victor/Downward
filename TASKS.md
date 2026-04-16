# TASKS.md

## Priority order

### P0 — Must do before broad feature work

1. Split navigation state ownership between compact and regular layouts
2. Prevent stale refresh results from being applied after a newer refresh completes
3. Harden the editor host boundary around text inset and scroll-indicator behavior

### P1 — Next hardening pass

4. Reduce observation fallback churn
5. Make workspace enumeration tolerant of partial failure
6. Explicitly choose and document the document write-durability policy

### P2 — Cleanup and feature-readiness

7. Remove legacy folder-route leftovers from live code and tests
8. Remove dead browser-row state / styling inputs
9. Audit task-owned busy/loading flags for guaranteed reset on cancellation

---

## 1. Split navigation state ownership

### Goal

Stop using one route array for both:

- compact stack history
- regular-width detail selection

### Files likely involved

- `Downward/App/AppSession.swift`
- `Downward/App/AppCoordinator.swift`
- `Downward/Features/Root/RootScreen.swift`
- `Downward/Shared/Models/AppRoute.swift`
- `Tests/WorkspaceNavigationModeTests.swift`
- `Tests/MarkdownWorkspaceAppSmokeTests.swift`

### Work

- add explicit regular-detail state to `AppSession`
- keep `session.path` as compact-stack state only
- update `presentSettings()` and `presentEditor(for:)` so they mutate the correct state for the current navigation mode or through a normalized shared API
- remove live dependence on `AppRoute.folder` if browsing no longer uses it
- normalize transitions when layout changes between compact and regular

### Acceptance criteria

- regular mode no longer needs stack history to decide what detail to show
- compact mode still uses `NavigationStack(path:)`
- repeated settings/editor switching does not grow hidden invalid state
- rotation between compact and regular keeps a sane visible destination

### Tests

- regular -> compact after opening settings then editor
- compact -> regular with open editor
- repeated settings/editor toggling leaves normalized state

---

## 2. Raise refresh generation protection to the application boundary

### Goal

Ensure only the newest workspace refresh can win.

### Files likely involved

- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/App/AppCoordinator.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Tests/MarkdownWorkspaceAppSmokeTests.swift`
- new focused refresh-race test if needed

### Work

- either stop stale snapshots from returning out of `WorkspaceManager`, or
- add coordinator-owned refresh generation and refuse to apply older results
- make foreground refresh and manual refresh share the same winner policy

### Acceptance criteria

- an older refresh result cannot overwrite a newer workspace snapshot in session state
- recent-files pruning and open-document reconciliation only happen against the winning snapshot

### Tests

- overlapping refreshes with delayed enumerator
- foreground refresh racing with pull-to-refresh

---

## 3. Harden the editor host boundary

### Goal

Make text inset behavior deterministic and future-proof enough for more editor features.

### Files likely involved

- `Downward/Features/Editor/EditorScreen.swift`
- possibly a new dedicated editor-host bridge file
- related previews or smoke tests

### Work

- move the text inset bridge out of the screen if it stays
- document why the bridge exists
- reduce or remove unstructured `DispatchQueue.main.async` usage if possible
- make the bridge lifecycle explicit for document switching and size changes
- keep scroll indicator edge-near while text content remains inset

### Acceptance criteria

- text inset stays stable across document switching
- text inset stays stable across iPad resize / rotation
- scroll indicator stays near the edge
- the implementation is isolated enough to support future editor polish

### QA

- iPhone portrait / landscape
- iPad portrait / landscape / split view resize
- rapid document switching

---

## 4. Reduce observation fallback churn

### Goal

Stop clean visible editors from revalidating forever on a fixed cadence when nothing changed.

### Files likely involved

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Tests/EditorConflictTests.swift`
- new observation-focused tests if needed

### Work

- add cheap metadata gating or backoff before yielding repeated synthetic changes
- treat fallback as degraded mode
- keep fallback alive only while it is actually needed

### Acceptance criteria

- no-change observation does not trigger repeated full revalidation forever at the current cadence
- external-change detection still works when presenter callbacks are unavailable

---

## 5. Make workspace enumeration tolerant of partial failure

### Goal

Allow the app to keep showing as much of the workspace as possible.

### Files likely involved

- `Downward/Infrastructure/WorkspaceEnumerator.swift`
- `Downward/Domain/Workspace/WorkspaceSnapshot.swift`
- logging if you decide to surface skipped nodes
- `Tests/WorkspaceEnumeratorTests.swift`

### Work

- define skip policy for unreadable descendants
- define policy for hidden/package/provider metadata folders
- continue building a partial snapshot unless the workspace root itself is unreadable

### Acceptance criteria

- one unreadable descendant does not fail the whole workspace refresh
- skipped content policy is documented

### Tests

- unreadable child folder fixture
- hidden subtree fixture
- partial snapshot still loads remaining siblings

---

## 6. Make the document write strategy explicit

### Goal

Turn the current direct-write choice into a documented product/architecture decision.

### Files likely involved

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `ARCHITECTURE.md`
- `QA_CHECKLIST.md`
- tests only if strategy changes

### Work

- decide whether to keep direct writes or move to a safer replacement strategy
- document why
- if staying with direct writes, document recovery expectations and provider rationale

### Acceptance criteria

- one clear section in docs explains the chosen save strategy
- future contributors do not have to infer the trust model from one code comment

---

## 7. Remove legacy folder-route leftovers

### Goal

Bring code, tests, and docs into alignment with the inline tree-browser model.

### Files likely involved

- `Downward/Shared/Models/AppRoute.swift`
- `Downward/Features/Root/RootScreen.swift`
- smoke tests
- previews relying on folder-route assumptions

### Work

- remove live uses of folder routes if no longer needed
- keep only what is still required for compatibility or explicit restore flows
- update docs/tests to the current product model

### Acceptance criteria

- there is one current answer to “how do folders behave in the browser?”
- live code no longer keeps obsolete navigation branches around without reason

---

## 8. Remove dead browser-row state

### Goal

Simplify workspace row APIs after the “currently open file” indicator removal.

### Files likely involved

- `Downward/Features/Workspace/WorkspaceRowView.swift`
- row call sites
- previews

### Work

- remove `isSelected` if it is now purely dead
- or restore a meaningful use if future selection styling is intentionally coming back

### Acceptance criteria

- row APIs match actual rendered behavior
- no dead styling inputs remain just to satisfy old call sites

---

## 9. Audit cancellation-safe UI state cleanup

### Goal

Make async UI state unwind correctly even when tasks are cancelled.

### Files likely involved

- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- any other task-owned busy/loading flows

### Work

- use `defer` where flags must always reset
- audit cancellation branches for stuck state risks

### Acceptance criteria

- busy/loading state cannot remain stuck after task cancellation
- repeated operations remain possible after a cancelled task

---

## Recommended next prompt order

1. navigation-state split
2. refresh-generation hardening
3. editor-host hardening
4. observation fallback reduction
5. enumeration policy
6. write-strategy decision
7. cleanup tasks

That order gives the biggest future-feature payoff first.
