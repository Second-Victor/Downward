# AGENTS.md

## Purpose

This repository is for **Downward**, a SwiftUI markdown editor for iPhone and iPad that works directly against a user-selected workspace folder from Files. The app must feel like a normal text editor: open a folder, browse nested files, edit plain text, autosave quietly, and only surface conflict UI for real exceptional cases.

This document tells engineers and coding agents how to work in this repository without regressing the app's file-safety and editor behavior.

---

## Source-of-truth order

When working in this repo, follow documents in this order:

1. `AGENTS.md` — coding rules, guardrails, and non-negotiable constraints
2. `PLANS.md` — product scope, UX intent, and success criteria
3. `ARCHITECTURE.md` — current system shape and file responsibilities
4. `TASKS.md` — execution order, backlog, and acceptance criteria

If there is a conflict between documents:

- prefer **user data safety**
- then prefer **seamless editor behavior**
- then prefer **the existing SwiftUI-first architecture**
- then prefer **the smallest change that preserves the current working save model**

---

## Product summary

Downward is a **folder-based file editor**, not a notes database.

Core product behaviors:

- user selects one workspace folder from Files
- the app stores persistent bookmark access to that workspace
- the workspace is restored on relaunch when possible
- the app browses nested folders and supported text files
- real folders remain visible in the browser even when they are currently empty or only contain unsupported files
- files open as plain UTF-8 text in `TextEditor`
- the active editor autosaves back to the real workspace file
- the active editor should not repeatedly interrupt the user with conflict UI during ordinary typing
- the app can revalidate and refresh the open document when it changes externally
- conflict UI is reserved for true exceptional cases such as delete/move or a real divergent external change that cannot be merged away quietly

The user-selected workspace remains the source of truth. Do not introduce an app-owned mirrored document store for MVP or near-MVP work.

---

## Hard constraints

### Platform and language

- Use **Swift 6.3 or newer**
- Support **iPhone** first and **iPad** with the same codebase
- Use **SwiftUI** for app UI
- Use **Observation** with `@Observable` for UI-facing state
- Use modern Swift concurrency
- Do not add macOS support unless explicitly requested

### UI framework rules

- Keep the UI layer SwiftUI-first
- Do not replace the editor with a custom text engine during MVP-plus work
- Do not move away from `TextEditor` unless explicitly requested
- Platform bridges are allowed only at clear infrastructure boundaries where SwiftUI does not provide a complete solution yet, such as folder picking or security-scoped file access
- Do not introduce UIKit-driven editor UI just to work around a product problem that can be solved in the existing architecture
- Use `#Preview` for UI files that render views

### Dependency rules

- Do not add third-party packages
- Prefer Apple frameworks already in use: `SwiftUI`, `Observation`, `Foundation`, `UniformTypeIdentifiers`, `CryptoKit`
- Add a new Apple framework only when it solves a real problem in the file or lifecycle model and the architecture docs are updated with the reason

### Persistence rules

- Do not introduce SwiftData for file contents
- Use lightweight persistence only for:
  - workspace bookmark data
  - last-open document session metadata
  - small app/session flags if needed
- Do not mirror workspace files into app-owned storage as the primary editing model
- The active document must save back to the user-selected workspace location
- Normal autosave should be silent for the active editor
- Do not reintroduce aggressive conflict prompts for routine typing

---

## Current product invariants

These behaviors are now part of the app's contract and must not be casually broken:

1. **Workspace-root editing**
   - Files are edited in place within the chosen workspace.
   - Relative paths inside the workspace matter.

2. **Editor buffer remains authoritative while typing**
   - A successful save acknowledgement must update the confirmed on-disk version without clobbering newer in-memory edits.
   - Newer keystrokes must survive older in-flight save completions.

3. **Conflict UI is exceptional**
   - Do not show conflict UI for the app's own ordinary autosave flow.
   - Only surface conflict resolution when the app cannot safely proceed silently.

4. **Revalidation must not self-conflict**
   - Foreground or live revalidation must not treat the app's own recent save as an external modification.

5. **Workspace mutations must stay coherent**
   - Create, rename, and delete must refresh the browser and keep editor/session state coherent.

---

## Engineering principles

### 1. File safety first

- Never silently discard in-memory edits
- Never regress the save pipeline into repeated self-conflicts
- Never assume bookmark access is valid without checking
- Treat Files/iCloud/provider operations as asynchronous and fallible
- Centralize reads, writes, reloads, revalidation, and conflict mapping

### 2. Seamless editing over noisy conservatism

- The active editor should behave like a normal text editor
- Autosave should be quiet when it succeeds
- Prefer calm recovery UX over repeated blocking prompts
- Preserve manual reload/overwrite flows for true edge cases

### 3. Small, explicit responsibilities

- Keep one primary type per file where practical
- Prefer clear domain names over vague utility names
- Keep file-system and persistence semantics out of Views
- Put coordination logic in managers/coordinators/view models, not in screens

### 4. Main-actor discipline

- UI-facing observable state belongs on `@MainActor`
- File I/O and digest/version work must not block the main actor
- Long-running tasks should be cancellable or generation-guarded
- Async completions must not overwrite newer state blindly

### 5. Testability over abstraction theatre

- Use protocols only where they create a real seam for tests or previews
- Prefer concrete types until there is a real need to abstract
- Save, conflict, restore, and mutation flows should remain easy to test in isolation

---

## Required project conventions

### Naming

Use the actual app/domain names that exist in the project:

- app entry point: `MarkdownWorkspaceApp`
- root composition: `AppContainer`
- root state owner: `AppSession`
- orchestration: `AppCoordinator`
- workspace domain: `WorkspaceManager`, `WorkspaceSnapshot`, `WorkspaceNode`
- document domain: `DocumentManager`, `OpenDocument`, `DocumentVersion`, `DocumentConflictState`

Do not reintroduce older names like `WorkspaceService` or `DocumentService` in new code unless the architecture docs are intentionally changed.

### File layout

Use the structure described in `ARCHITECTURE.md`. Do not create parallel feature trees without updating that document first.

### One responsibility per Swift file

Good examples:

- `AppCoordinator.swift` coordinates workspace, editor, and restore flows
- `WorkspaceManager.swift` owns workspace selection and mutations
- `DocumentManager.swift` owns document open/reload/revalidate/save
- `EditorViewModel.swift` owns editor text, autosave, and conflict presentation state

Bad examples:

- `AppStuff.swift`
- `Helpers.swift`
- giant mixed files containing unrelated screens, models, and services

### Documentation comments

Add concise documentation comments to:

- save/revalidation methods
- conflict handling logic
- any live-refresh or external-change reconciliation logic
- bookmark/session restore boundaries
- any non-obvious file mutation or path-rewrite code

---

## Swift style rules

- Prefer value types for immutable models
- Prefer `actor` for serialized file/persistence boundaries
- Avoid force unwraps and `try!`
- Prefer explicit error handling and user-facing recovery paths
- Prefer structured concurrency over GCD
- Prefer generation checks when async work can race with newer state
- Prefer small pure helpers for path/version/conflict transforms

---

## Rules for future document and save work

Any future work touching `DocumentManager`, `EditorViewModel`, `AppCoordinator`, or workspace mutation flows must preserve all of the following:

- successful save acknowledgements update the confirmed disk version
- newer local edits are preserved if a save finishes late
- routine autosave does not trigger repeated conflict UI
- revalidation does not self-conflict after the app's own saves
- delete/move handling remains explicit and recoverable
- tests are updated or added for any changed save/conflict behavior

If a proposed change makes the save model noisier, more manual, or more popup-heavy, treat that as a regression unless the user explicitly requested it.

---

## Real-device QA checklist

Before treating persistence, restore, mutation, or conflict work as release-ready, verify the app on a real iPhone or iPad with both local Files storage and iCloud Drive when available.

Minimum manual QA pass:

1. Select a workspace from Files, relaunch the app, and confirm the workspace restores.
2. Open a file, type normally, and confirm autosave stays calm with no repeated conflict prompts.
3. Edit the same file externally or on another device and confirm the active editor refreshes calmly when safe.
4. Rename the open file and confirm the editor stays attached to the renamed file.
5. Delete the open file and confirm the app leaves the editor in a sane recovery state.
6. Switch rapidly between files and confirm no stale editor title, text, or save state remains visible.
7. Background and foreground the app during edits and after external changes, then confirm revalidation stays coherent.
8. Relaunch with a valid last-open file and with a missing last-open file; confirm restore is calm in both cases.
9. Repeat the core flows once with `On My iPhone` / `On My iPad` storage and once with iCloud Drive if available.

If a simulator-only run passes but a real-device pass reveals provider timing or access issues, prefer documenting the limitation and adding targeted diagnostics/tests over broad architectural churn.
