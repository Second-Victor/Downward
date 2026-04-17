# TASKS.md

## Purpose

This file is the **active forward backlog** for Downward.

The big hardening sprint is done. The project no longer needs a “save the architecture” phase.
What it needs now is disciplined, incremental work that:

1. preserves the file-safety and editor-state guarantees already earned,
2. avoids re-centralizing behavior in the biggest pressure-point files,
3. prepares the app for richer browser, editor, and settings features.

This file should drive the next coding passes.

---

## Release-safety guardrails

These are not open tasks. They are current invariants that future work must not regress.

- Browser/search-driven file open must prefer **trusted workspace-relative identity** over raw URL re-derivation.
- The app must not surface or mutate redirected descendants outside the chosen workspace.
- Refreshes and mutations must remain ordered by one explicit workspace-snapshot winner policy.
- Document load/revalidate reads must stay cancellation-aware.
- Write/mutation detachment, where it remains, must stay an explicit exception with comments and tests.
- The app still owns **one active live document session at a time**.

---

## Highest-priority next work

## 1. Add one focused browser/editor regression pass around open identity

**Problem**

The recent “Document Unavailable” regression showed that browser rows, search results, pending editor presentation, and regular iPad detail rendering can drift if they stop agreeing on the same file identity.

**Why it matters**

This is the most important recently-fixed failure. It should not regress quietly.

**What success looks like**

- tests explicitly prove tree open, search open, and regular-detail editor loading all use the same trusted relative-path identity,
- route URL differences no longer matter when the logical relative path is the same,
- the repo has one short documented explanation of this identity rule.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/App/AppCoordinator.swift`
- `Downward/App/AppSession.swift`
- `Tests/MarkdownWorkspaceAppSmokeTests.swift`
- `Tests/WorkspaceNavigationModeTests.swift`
- `Tests/DocumentManagerTests.swift`

---

## 2. Keep shrinking pressure inside `AppCoordinator` without changing the architecture

**Problem**

`AppCoordinator.swift` is still the main place where cross-domain behavior naturally wants to accumulate.

**Why it matters**

The coordinator is healthy enough today, but it is still the file most likely to get worse as new features land.

**What success looks like**

- new behavior lands in existing policy seams before it lands inline in the coordinator,
- 1–2 additional dense policy clusters are extracted only if they are truly shared and stable,
- the coordinator remains the orchestrator rather than a grab-bag implementation file.

**Likely affected areas/files**

- `Downward/App/AppCoordinator.swift`
- `Downward/App/WorkspaceNavigationPolicy.swift`
- `Downward/App/WorkspaceSessionPolicy.swift`
- small supporting helper types only if clearly justified

---

## 3. Split the next layer of `PlainTextDocumentSession` only when feature work demands it

**Problem**

`PlainTextDocumentSession.swift` still owns a large amount of behavior.

**Why it matters**

The file is currently correct enough, but it remains the most delicate place to change when editor behavior grows.

**What success looks like**

- future work identifies a real seam before adding complexity,
- likely candidates stay narrow, such as observation policy, coordinated read/write helpers, or conflict mapping,
- no speculative file-splitting happens without a concrete benefit.

**Likely affected areas/files**

- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/Domain/Document/DocumentManager.swift`

---

## Product groundwork

## 4. Expand settings safely

**Problem**

The app now has a stable enough foundation for more editor/browser preferences, but settings growth can easily leak into unrelated files if not kept disciplined.

**Why it matters**

This is one of the easiest feature areas to grow next, and it should not become a side-channel for architecture drift.

**What success looks like**

- new settings remain owned by dedicated persistence and view-model seams,
- settings changes do not require coordinator sprawl,
- settings previews and tests stay current.

**Likely affected areas/files**

- `Downward/Features/Settings/SettingsScreen.swift`
- `Downward/Domain/Persistence/EditorAppearanceStore.swift`
- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/App/AppContainer.swift`

---

## 5. Add richer editor UX without changing the save/conflict contract

**Problem**

The app is now ready for richer editor work, but editor improvements are the easiest place to accidentally reintroduce noisy conflict behavior or stale-state bugs.

**Why it matters**

This is likely where the product will gain the most visible value next.

**What success looks like**

- new editor features stay on top of the existing live document/session model,
- autosave remains calm,
- conflict UI stays exceptional,
- document switching and background/foreground behavior remain coherent.

**Likely affected areas/files**

- `Downward/Features/Editor/EditorViewModel.swift`
- `Downward/Features/Editor/EditorScreen.swift`
- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Tests/EditorAutosaveTests.swift`
- `Tests/EditorConflictTests.swift`

---

## 6. Improve browser polish without regressing identity correctness

**Problem**

The sidebar tree is now structurally correct, but future browser polish could accidentally reintroduce URL-first logic or stale expansion/selection assumptions.

**Why it matters**

The browser is now one of the main product surfaces.

**What success looks like**

- row/UI work remains presentation-only,
- expansion state keeps using relative identity,
- browser/search/recent-file opens stay aligned with the current trusted identity model.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Features/Workspace/WorkspaceRowView.swift`
- `Downward/Features/Workspace/WorkspaceSearchRowView.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`

---

## Medium-priority architecture cleanup

## 7. Consolidate route/document identity documentation in code comments

**Problem**

The code now has a sound route/relative-path model, but the rationale is spread across several files.

**Why it matters**

This is exactly the kind of thing future contributors can accidentally break if the rule is only obvious after reading multiple patches.

**What success looks like**

- a short, consistent explanation exists in the few files that actually own the rule,
- future route/open changes have an obvious place to start.

**Likely affected areas/files**

- `Downward/App/AppCoordinator.swift`
- `Downward/App/AppSession.swift`
- `Downward/Features/Workspace/WorkspaceFolderScreen.swift`
- `Downward/Domain/Document/DocumentManager.swift`

---

## 8. Keep search intentionally simple until there is a real scale trigger

**Problem**

The current search model is appropriate, but it has a known ceiling.

**Why it matters**

Future content search or very large workspaces should begin with an explicit scaling discussion, not by accreting more work inside `WorkspaceViewModel`.

**What success looks like**

- filename/path search remains clean and responsive,
- content search or large-workspace work starts from a design note rather than opportunistic changes,
- docs keep the current limit visible.

**Likely affected areas/files**

- `Downward/Features/Workspace/WorkspaceViewModel.swift`
- `Downward/Features/Workspace/WorkspaceSearchEngine.swift`
- `ARCHITECTURE.md`
- `PLANS.md`

---

## Low-priority cleanup

## 9. Keep previews and sample data aligned with the real product model

**Problem**

Preview/sample support tends to drift after navigation, browser, and row-layout changes.

**Why it matters**

Stale previews reduce confidence during future UI work.

**What success looks like**

- previews reflect the current browser/search/editor product,
- sample data supports duplicate filenames, nested folders, and empty/document-missing cases,
- preview-only helpers do not imply dead live behavior.

**Likely affected areas/files**

- `Downward/Shared/PreviewSupport/PreviewSampleData.swift`
- SwiftUI preview blocks in workspace/editor/root screens

---

## 10. Revisit large-file organization only when it improves real velocity

**Problem**

Several files remain large, but not every large file needs immediate splitting.

**Why it matters**

Premature splitting can create abstraction noise with little benefit.

**What success looks like**

- future splits happen because a real policy seam is ready,
- the repo stays navigable,
- no “cleanup for cleanup’s sake” churn is introduced.

**Likely affected areas/files**

- `Downward/App/AppCoordinator.swift`
- `Downward/Domain/Workspace/WorkspaceManager.swift`
- `Downward/Domain/Document/PlainTextDocumentSession.swift`
- `Downward/Features/Workspace/WorkspaceViewModel.swift`
