# AGENTS.md

## Purpose

This repository is for **Downward**, a SwiftUI markdown editor for iPhone and iPad that works directly against a user-selected workspace folder from Files.

Use this document as the top-level steering guide for contributors and coding agents.
It defines the non-negotiable product rules, architectural guardrails, and repo workflow expectations.

---

## Source-of-truth order

Use the repo docs in this order:

1. `AGENTS.md` — guardrails, invariants, and contribution rules
2. `ARCHITECTURE.md` — current system shape and ownership boundaries
3. `TASKS.md` — active backlog, known pressure points, and current priorities
4. `PLANS.md` — detailed technical checklists, performance plans, and code-review findings

Older steering docs were intentionally folded into these files.
If a proposal conflicts with the docs, prefer:

1. user data safety,
2. calm editor behavior,
3. the current workspace-relative identity model,
4. the smallest change that preserves the shipping save model.

---

## Product summary

Downward is a **folder-based file editor**, not a notes database.

Core behaviors:

- the user selects one workspace folder from Files,
- the app stores bookmark-based access to that folder,
- the workspace restores on relaunch when possible,
- the browser shows nested folders and supported text files,
- the editor opens and saves the real file in place,
- autosave is quiet during ordinary typing,
- conflict UI is reserved for exceptional cases,
- recent files, search, restore, and mutation flows all stay aligned to trusted workspace-relative identity.

The chosen workspace remains the source of truth.
Do not introduce an app-owned mirrored document store for normal editing.

---

## Hard constraints

### Platform and language

- Use **Swift 6+**.
- Support **iPhone** and **iPad** with the same codebase.
- Keep the UI **SwiftUI-first**.
- Use modern Swift concurrency.
- Use `@Observable` for UI-facing state where it already fits the codebase.
- Do not add macOS support unless explicitly requested.

### Dependencies

- Do not add third-party packages.
- Prefer Apple frameworks already in use.
- Add a new framework only for a clear product or platform boundary, then update `ARCHITECTURE.md`.

### Persistence and file model

- Do not use SwiftData for workspace file contents.
- Persist only lightweight app state such as bookmarks, session metadata, recents, and editor appearance.
- The active document must save back to the real workspace file.
- Normal autosave must stay silent.
- Do not reintroduce noisy or repeated conflict prompts.

---

## Current product invariants

These are part of the app contract and must not be casually broken.

1. **Workspace-relative identity is primary**
   - Browser, search, restore, and recents should prefer trusted relative paths when they already know them.
   - Raw URL-only open flows are compatibility paths, not the preferred product model.

2. **The editor buffer remains authoritative while typing**
   - A late save completion must not clobber newer in-memory edits.
   - Successful saves must still update the confirmed on-disk version.

3. **Conflict UI is exceptional**
   - Routine autosave should not surface conflict UI.
   - Only real divergent external changes, missing files, or unrecoverable situations should escalate.

4. **Revalidation must not self-conflict**
   - Foreground refresh or live observation must not treat the app's own save as an external modification.

5. **Workspace mutations stay coherent**
   - Create, rename, delete, refresh, restore, and reconnect flows must keep browser, route, recents, and editor state coherent.

6. **The app currently owns one active live document session**
   - Do not accidentally introduce multi-document live-session behavior without an explicit design pass.

---

## Engineering principles

### 1. File safety first

- Never silently discard in-memory edits.
- Never bypass workspace-boundary validation at the final file-system edge.
- Treat Files and provider-backed URLs as asynchronous and fallible.
- Keep reads, writes, reloads, and mutation handling in the domain/infrastructure layers, not in Views.
- Reuse already-loaded or already-encoded UTF-8 buffers in document-session versioning paths instead of adding avoidable full-buffer round-trips.

### 2. Calm editing over defensive noise

- The app should feel like a normal text editor.
- Autosave should be quiet when safe.
- Recovery UI should be clear but rare.
- Prefer calm refresh behavior over popup-heavy workflows.

### 3. Small, explicit responsibilities

- Keep one primary type per file where practical.
- Prefer domain names over generic helpers.
- Keep feature and view code out of file-system and persistence logic.
- Extend existing policy seams before adding more coordinator logic.

### 4. Main-actor discipline

- UI-facing observable state belongs on the main actor.
- File I/O and heavier file-version work should not block the main actor.
- Async completions must not overwrite newer state blindly.
- Use generation checks where newer work can race with older completions.
- Classify every new unstructured `Task` as app/session-owned, model-owned, view-owned, or explicitly fire-and-forget.
- Model-owned tasks that mutate state after `await` must cancel or check identity/generation when the selected workspace, route, or document changes.
- Fire-and-forget UI actions are acceptable only when a coordinator/domain boundary owns stale-result suppression.

### 5. Testability over abstraction theatre

- Use protocols only where they provide a real seam.
- Prefer concrete types until a test or runtime boundary needs abstraction.
- Save, restore, revalidation, mutation, and navigation flows should remain easy to test in isolation.

---

## Required project conventions

### Naming and ownership

Use the current app/domain names already present in the codebase:

- app entry point: `MarkdownWorkspaceApp`
- root composition: `AppContainer`
- root session state: `AppSession`
- orchestration: `AppCoordinator`
- app policy seams: `WorkspaceNavigationPolicy`, `WorkspaceSessionPolicy`, `WorkspaceMutationPolicy`
- app mutation seams: `WorkspaceMutationService`, `WorkspaceMutationErrorPresenter`
- workspace domain: `WorkspaceManager`, `WorkspaceSnapshot`, `WorkspaceNode`
- document domain: `DocumentManager`, `PlainTextDocumentSession`, `OpenDocument`
- editor UI: `EditorViewModel`, `EditorScreen`, `MarkdownEditorTextView`

Do not reintroduce older names like `WorkspaceService` or `DocumentService` unless the architecture is intentionally changed.

### File layout

Follow the structure in `ARCHITECTURE.md`.
Do not create parallel feature trees or alternate ownership paths without updating that document.

### Editor rules

- The current editor is **not** `TextEditor` anymore.
- The shipping editor is a SwiftUI-hosted `UITextView` boundary via `MarkdownEditorTextView`.
- Do not replace it casually.
- Do not add a second competing editor implementation.
- Keep editor-specific UI behavior out of `PlainTextDocumentSession` unless it is truly part of the file session contract.

### Settings rules

- Keep Settings navigation and visual hierarchy inside the Settings feature.
- Wire real settings through existing stores such as `EditorAppearanceStore`.
- Keep workspace actions delegated to the root/coordinator flow; do not move file-system or bookmark logic into Settings views.
- Leave JSON theme import/export, StoreKit tips, App Store review routing, legal URLs, and custom theme persistence visibly placeholder-only until their backing infrastructure is implemented.

### Documentation comments

Add concise comments to:

- save and revalidation paths,
- conflict handling,
- bookmark and restore boundaries,
- path-validation logic,
- non-obvious editor chrome or layout calculations.

---

## Swift style rules

- Prefer value types for immutable models.
- Prefer `actor` for serialized file or persistence boundaries.
- Avoid force unwraps and `try!` in production code.
- Prefer explicit error handling and user-facing recovery paths.
- Prefer structured concurrency over ad hoc task trees.
- Prefer pure helpers for path, version, and conflict transforms.

---

## Real-device QA gate

Before treating editor, restore, mutation, or file-access work as release-ready, verify on a real iPhone or iPad.

Minimum manual pass:

1. choose a workspace and relaunch to confirm restore,
2. open a file and type long enough for autosave to occur,
3. switch rapidly between files,
4. rename and delete an open file,
5. background and foreground the app,
6. verify the editor top chrome and first visible line on both iPhone and iPad,
7. repeat the core flow once with local Files storage and once with iCloud Drive when available.

If simulator behavior and real-device behavior differ, trust the real-device result and update tests or diagnostics accordingly.
