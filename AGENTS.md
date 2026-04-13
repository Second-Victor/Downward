# AGENTS.md

## Purpose

This repository is for a **SwiftUI-only markdown editor** for iPhone and iPad. The product goal is a calm, reliable editor that lets the user choose a folder from Files, browse nested folders, open markdown files, edit them as plain text, and save safely.

This file tells any engineer or coding agent how work must be done in this repository.

---

## Source-of-truth order

When working in this repo, follow documents in this order:

1. `AGENTS.md` — coding rules, repo conventions, and non-negotiable constraints
2. `PLANS.md` — product scope, MVP boundaries, and success criteria
3. `ARCHITECTURE.md` — structure, file responsibilities, and system design
4. `TASKS.md` — execution order and acceptance criteria

If there is a conflict:

- prefer **data safety and save correctness**
- then prefer **SwiftUI-only implementation**
- then prefer **the smallest MVP that satisfies the user story**
- do not add clever abstractions that expand scope without solving a real problem

---

## Product summary

Build a minimal but robust markdown editor with these core behaviors:

- user selects **one workspace folder** from Files
- app stores persistent access to that folder with a bookmark
- app restores the folder on relaunch when possible
- app recursively browses nested folders and markdown files
- app opens markdown files as plain text
- app edits with `TextEditor`
- app autosaves safely
- app detects save conflicts before overwriting newer disk content
- app keeps the UI minimal and native

This is not a notes database. It is a **folder-based file editor**.

---

## Hard constraints

### Platform and language

- Use **Swift 6.3 or newer**
- Use **SwiftUI only**
- Use **Observation** with `@Observable` for UI-facing models
- Use modern Swift concurrency
- Support **iPhone** first
- Support **iPad** with the same codebase and adaptive layout
- Do not add macOS support during MVP unless explicitly requested

### UI framework rules

- Do not introduce UIKit or AppKit
- Do not wrap `UIViewController`, `UITextView`, or `UIDocumentPickerViewController`
- Do not switch away from `TextEditor` during MVP
- Use SwiftUI presentation and navigation APIs only
- Use `#Preview` for every view file that renders UI

### Dependency rules

- Do not add third-party packages
- Use only Apple frameworks already available in the SDK unless explicitly approved
- Prefer Foundation, SwiftUI, Observation, UniformTypeIdentifiers, and CryptoKit only where needed

### Persistence rules

- Do not introduce SwiftData for MVP
- Use lightweight persistence only for:
  - workspace bookmark data
  - last opened file reference
  - simple session restore metadata if implemented
- Keep file contents in the user-selected folder rather than copying them into app-owned storage

---

## MVP boundaries

### Must be in MVP

- choose a folder
- persist workspace access
- restore workspace access on launch
- browse nested folders
- open `.md` and `.markdown` files
- optionally support `.txt`
- edit as plain text
- autosave
- safe save conflict detection
- create file
- rename file
- delete file
- empty states
- error states
- previews for UI views
- sample data for previews
- unit tests for core file and save logic

### Must not be in MVP

- live markdown preview
- syntax highlighting
- custom text engine
- Git integration
- plugin system
- sync engine
- tag database
- backlinks or wiki links
- multiple windows
- tabbed editing
- custom keyboard accessory bar full of formatting buttons
- custom storage layer that mirrors the workspace

---

## Engineering principles

### 1. File safety first

- Never silently discard unsaved edits
- Never silently overwrite a newer on-disk version
- Never assume a folder bookmark is valid without checking
- Always treat Files/iCloud provider behavior as asynchronous and fallible
- Centralize all reads, writes, moves, deletes, and metadata checks

### 2. SwiftUI purity

- The app must remain SwiftUI-only
- If a task seems easier in UIKit, stop and document the limitation rather than silently bridging
- The MVP should be shaped around what SwiftUI can do well:
  - `NavigationStack`
  - `TextEditor`
  - `fileImporter`
  - sheets, alerts, confirmation dialogs, and overlays

### 3. Small clear files

- One primary type per file
- Keep file responsibilities narrow and named clearly
- Prefer explicit feature folders over giant utility folders
- Put business logic into services and view models, not Views

### 4. Main actor discipline

- UI-facing observable state belongs on `@MainActor`
- File I/O must not run on the main actor
- Long-running work must be cancellable
- Async results must not overwrite newer state

### 5. Testability over cleverness

- Prefer simple protocols or lightweight seams only where they improve testability
- Use concrete types until abstraction is needed
- Services should be easy to fake for previews and tests
- Avoid architecture that exists only to look “clean”

---

## Required project conventions

### Naming

- App entry point uses `MarkdownWorkspaceApp`
- Types use clear nouns:
  - `WorkspaceService`
  - `DocumentService`
  - `WorkspaceBrowserViewModel`
  - `DocumentEditorScreen`
- Avoid vague names like `Manager2`, `Helper`, `Thing`, or `DataStore` without a domain prefix

### File layout

Use the structure defined in `ARCHITECTURE.md`. Do not invent parallel structures unless the architecture file is updated first.

### One responsibility per Swift file

Each Swift file must have one clear job. Good examples:

- `WorkspaceNode.swift` defines the tree node type
- `WorkspaceEnumerator.swift` walks the directory tree
- `WorkspaceNodeRow.swift` renders one row
- `DocumentEditorViewModel.swift` owns editor state and actions

Bad examples:

- `WorkspaceStuff.swift`
- `Utilities.swift`
- a single file containing unrelated models, views, services, and extensions

### Documentation comments

Add documentation comments to:

- public or internal services with non-obvious behavior
- save pipeline methods
- bookmark restoration methods
- conflict handling logic
- preview sample factories if their intent is not obvious

Short comments are enough. Do not narrate obvious code.

---

## Swift style rules

- Prefer value types for immutable models
- Prefer `actor` for stateful file I/O services when serialization matters
- Avoid force unwraps
- Avoid `try!`
- Prefer explicit error handling and user-facing recovery paths
- Prefer `Task` and structured concurrency over GCD
- Prefer `Task.sleep(for:)` over nanosecond-based sleep
- Prefer `URL.appending(path:)` where appropriate
- Prefer `localizedStandardCompare(_:)` or similar user-friendly sorting for visible file names
- Prefer `localizedStandardContains(_:)` when filtering user-entered search text
- Keep async work cancellable
- Do not put file system side effects in property observers

---

## SwiftUI style rules

- Use `NavigationStack` for the baseline MVP navigation flow
- Keep iPad adaptation additive, not architecture-breaking
- Use `foregroundStyle()` instead of `foregroundColor()`
- Use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`
- Use `Button` instead of `onTapGesture()` for primary interactions
- Use separate `View` types instead of large computed subviews
- Do not over-style the interface
- Respect Dynamic Type
- Do not hard-code tiny font sizes
- Keep spacing mostly system-driven
- Do not use `AnyView` unless there is no practical alternative
- Avoid giant custom view modifiers for simple styling
- Keep editor chrome minimal

---

## Observation rules

- Use `@Observable` for UI-facing state owners
- Mark observable view models `@MainActor`
- Do not use `ObservableObject` for new code
- Keep derived UI state inside the view model when it is reused by more than one view
- Do not let Views derive complex save/conflict logic on their own

---

## File-system rules

### Workspace access

- Workspace access starts from a user-selected folder
- Persist access using bookmark data
- Restore bookmark data on launch
- Treat stale bookmark resolution as a first-class recovery state
- Encapsulate `startAccessingSecurityScopedResource()` usage in one place

### Reads and writes

- Read file contents through `DocumentService`
- Enumerate folders through `WorkspaceService`
- Coordinate writes centrally
- Use atomic or replace-based writes where practical
- Refresh metadata after successful save
- Re-check file version before overwrite

### Conflict handling

- Store the loaded version for an open document
- Before saving, compare current disk metadata with loaded metadata
- If the file changed externally, move into conflict state
- Present user choices rather than overwriting silently

---

## View rules

### Every view file must have previews

Any SwiftUI view that renders UI must include at least one `#Preview`.

For screens with distinct states, include multiple previews when useful:

- empty
- loading
- populated
- dirty
- saving
- conflict
- error

### Every preview must use sample data

Do not create empty previews that do not demonstrate the real state of the screen.

Use shared preview data from `PreviewSupport/`.

Examples of preview-worthy states:

- `WorkspacePickerScreen` with no workspace
- `ReconnectWorkspaceScreen` with a stale bookmark message
- `WorkspaceBrowserScreen` with a nested tree
- `FolderContentsScreen` with mixed folders and files
- `DocumentEditorScreen` with:
  - clean content
  - unsaved content
  - failed save
  - conflict warning

### Preview ownership

- Sample models belong in `PreviewSampleData.swift`
- Fake services for preview-only injection belong in `PreviewServices.swift`
- Do not bury random sample values inside multiple unrelated view files unless they are tiny and truly local

---

## Testing rules

### Unit tests are required for

- bookmark persistence
- bookmark restore failure handling
- file filtering and supported extensions
- folder tree construction
- sorting rules
- document dirty-state transitions
- debounced autosave
- save conflict detection
- create / rename / delete file operations
- stale async result rejection where applicable

### UI tests are useful for

- first launch no-workspace flow
- workspace picker presentation
- nested folder browsing
- opening a document
- typing and autosave behavior
- conflict alert presentation
- create / rename / delete flows

### Test philosophy

- prioritize unit tests for services and view models
- add UI tests for end-to-end confidence on the highest-risk flows
- do not write fragile UI tests for minor layout details

---

## Definition of done for any change

A change is not done until all of the following are true:

- code matches the current task in `TASKS.md`
- architecture boundaries are respected
- the change does not expand scope unintentionally
- relevant previews compile and show realistic data
- relevant tests pass or are added
- no direct file I/O was added to a View
- no save semantics were weakened
- no conflict path was bypassed
- naming is consistent with the repo

---

## Common mistakes to avoid

- using `TextEditor` state directly as the source of truth without a view model
- putting bookmark restore logic in a View
- making file operations from button actions inside the view body
- flattening the workspace into a single file list
- removing folders that only contain supported descendants deeper in the tree
- hiding the unsaved indicator as soon as saving starts
- assuming save success before disk confirmation
- creating a giant all-purpose app state object with every detail in it
- introducing UIKit “just for one thing”
- adding live preview or syntax highlighting before the save pipeline is solid

---

## Implementation mindset

When choosing between two approaches, prefer the one that is:

1. safer for user data
2. smaller in scope
3. easier to test
4. more native to SwiftUI
5. easier to preview

A smaller and reliable markdown editor is better than a more ambitious but fragile one.