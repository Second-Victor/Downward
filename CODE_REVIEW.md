# CODE_REVIEW.md

## Scope

This review covered the current Downward repository after the recent iPhone/iPad tree-browser and editor inset work.

Reviewed areas:

- app/session/coordinator flow
- compact vs regular navigation shells
- workspace browser and search UI
- workspace restore, refresh, recent files, and mutations
- document open/save/revalidate/observe pipeline
- settings and editor appearance persistence
- existing unit and smoke tests

This was a **static review**. I did **not** run `xcodebuild` in this environment, so anything that depends on device-only Files provider behavior, iPad size-class transitions, or runtime TextEditor internals still needs QA on device.

---

## Overall assessment

The repo is in a much better place than a typical SwiftUI file editor MVP.

What is already strong:

- the app has a clear split between `AppCoordinator`, `WorkspaceManager`, `DocumentManager`, and feature view models
- canonical relative-path identity is used much more consistently than before
- coordinated workspace mutations are now in place
- the editor save acknowledgement merge model is still the strongest part of the codebase
- the test suite is broad enough that you can harden the app without guessing blindly

The app is **good enough to keep building on**, but I would still treat it as **pre-hardening**, not “future-feature ready.”

The main risks are no longer basic MVP issues. They are now:

1. navigation state complexity after the move from folder routes to an inline tree
2. fragile editor inset customization sitting on top of `TextEditor`
3. overlapping refresh / observation behavior that is still slightly too loose at the coordinator boundary
4. file-system policy decisions that are present in code but not fully owned as product/architecture decisions yet

---

## What improved since the earlier review

These are meaningful improvements and should be kept:

### 1. Canonical identity is in much better shape

`RecentFilesStore` now prunes using `WorkspaceRelativePath.make(...)` from real URLs rather than rebuilding file identity from display names. Search results also use canonical relative paths.

### 2. Workspace mutations are now coordinated

`LiveWorkspaceManager` now routes create / rename / delete through `WorkspaceFileCoordinating` and `NSFileCoordinator`, which is a real step up from the earlier direct `FileManager` / `Data.write` browser mutations.

### 3. Inline tree browsing is the right product direction

The browser now behaves more like a real file browser. Expansion state is keyed by canonical folder-relative paths, which is the correct identity model for future polish.

### 4. The editor lifecycle is better guarded than before

`EditorViewModel.handleDisappear(for:)` now invalidates pending loads and stops observation. That closes the most obvious “late load resurrects a closed editor” hole.

---

## Findings

## P1 — Navigation state is now doing double duty across compact and regular layouts

### Evidence

- `AppSession.path` is still the single shared route stack.
- `CompactWorkspaceShell` binds `NavigationStack(path: $session.path)` directly.
- `RegularWorkspaceShell` does **not** bind detail UI to that same stack, but `AppSession.regularWorkspaceDetail` still derives detail selection partly from `path.last`.
- `AppCoordinator.presentSettings()` appends `.settings` to `session.path`.
- `AppCoordinator.presentEditor(for:)` also mutates `session.path` in both size classes.
- `AppRoute.folder` still exists even though normal browsing no longer uses folder-route navigation.

### Why it matters

The app now has two navigation models:

- compact: real path-driven stack navigation
- regular: effectively selection/detail rendering with path history piggybacked on top

That means `session.path` is carrying both:

- user-visible stack history in compact mode
- implementation-detail state for regular-width detail rendering

This is workable today, but it is a fragile base for future features like:

- better iPad detail behavior
- rotation between compact and regular size classes
- search-to-editor transitions
- settings/editor switching
- future multi-document or tab work

It is also easy for stale regular-mode routes to accumulate and then reappear when the app later collapses into a compact stack.

### Recommendation

Split navigation concerns explicitly:

- keep `session.path` for compact `NavigationStack` history only
- add a separate regular-width detail selection model, for example:
  - `.placeholder`
  - `.settings`
  - `.editor(relativePath or URL)`
- remove `AppRoute.folder` from live navigation if it is no longer part of the product model
- make rotation / size-class transitions normalize path/detail state intentionally instead of implicitly

### Suggested tests

- open settings in regular mode, then open a file, then rotate to compact and assert the stack is sane
- open an editor in compact mode, rotate to regular, then back again
- verify repeated settings/editor switching does not grow an invalid hidden route history

---

## P1 — Workspace refresh generation protection still stops only the cache overwrite, not the caller overwrite

### Evidence

- `LiveWorkspaceManager.loadSnapshot(...)` increments `refreshGeneration` and only writes `currentSnapshot` when the generation still matches.
- the same method still **returns** its snapshot even if it is stale relative to a newer in-flight refresh.
- `AppCoordinator.refreshWorkspace()` and `handleSceneDidBecomeActive()` still apply the returned snapshot directly.

### Why it matters

You have generation protection in the manager, but not yet at the full call chain boundary.

So two overlapping refreshes can still race like this:

1. refresh A starts
2. refresh B starts
3. B finishes first and becomes the newest snapshot
4. A finishes later and is still returned to the coordinator
5. the coordinator applies A back into session state

That risk is more important now because the browser tree, recent-files pruning, and open-document reconciliation all depend on the current snapshot being authoritative.

### Recommendation

Choose one of these and make it explicit:

1. stale manager refreshes should throw/cancel and never return a stale snapshot, or
2. the coordinator should own a refresh generation and refuse to apply an older result

Right now the generation boundary is not high enough.

### Suggested tests

- delayed enumerator with two overlapping refreshes
- one refresh triggered by pull-to-refresh and another by foreground activation
- assert the older result cannot overwrite the newer session snapshot

---

## P1 — The new editor inset solution is functional, but still fragile and under-tested

### Evidence

`EditorScreen` now uses a `TextEditorInsetConfigurator` that:

- embeds a blank `UIViewRepresentable` in the `TextEditor` background
- crawls the UIKit view tree looking for the nearest `UITextView`
- mutates `textContainerInset` and `lineFragmentPadding`
- does so inside `DispatchQueue.main.async` during `updateUIView`

### Why it matters

This is a valid tactical workaround, but it is still a brittle bridge around `TextEditor` internals.

Risks:

- future SwiftUI / TextEditor hierarchy changes can break the subview search
- inset application is not owned by a stable dedicated text-view wrapper
- the deferred `DispatchQueue.main.async` write can race with view teardown, document switching, focus changes, or repeated updates
- there is no test or smoke coverage around this behavior

This area is important because editor polish and future features like syntax themes, selection helpers, find-in-file, or toolbar changes will probably touch the same boundary.

### Recommendation

Treat the current inset configurator as a short-term compatibility layer.

Hardening options:

- keep `TextEditor`, but isolate the bridge into a dedicated editor-host file with explicit lifecycle rules and no ad hoc view-tree crawling spread through the screen
- or move to a thin `UITextView` wrapper **only if** you explicitly decide the app is leaving the “pure TextEditor” phase

Even if you keep `TextEditor`, the current code should be hardened with:

- one owned bridge type
- no unstructured GCD if it can be avoided
- explicit comments about why the bridge exists
- preview / smoke coverage focused on focus changes, document switching, and iPad resizing

### Suggested tests / QA

- open document A, then quickly open B, and verify inset stays correct
- rotate iPad and resize split view while typing
- verify the scroll indicator remains edge-near while text inset stays stable
- add a small smoke test or bridge-focused preview fixture if practical

---

## P2 — Observation fallback still emits synthetic change signals forever

### Evidence

- `PlainTextDocumentSession.startObservationFallbackIfNeeded()` starts a task that yields a change every 3 seconds
- `EditorViewModel.startObservingDocumentChanges(for:)` revalidates on each event whenever the visible editor is clean and not currently saving

### Why it matters

This means a clean, visible editor can keep performing coordinated reads forever even when nothing changed.

That may still be acceptable as a temporary degraded mode, but it is not a good steady-state architecture for:

- battery
- provider-backed folders
- perceived responsiveness on large or cloud-backed workspaces
- future features layered onto the editor lifecycle

### Recommendation

Turn the fallback into a real degraded-mode policy rather than a constant timer:

- gate on last known file metadata before revalidating
- back off when repeated checks show no changes
- only keep the fallback alive while presenter delivery appears unreliable
- consider making the fallback interval adaptive instead of fixed

### Suggested tests

- no-change observation should not cause repeated full revalidation on a tight cadence
- presenter-available path should avoid fallback churn

---

## P2 — Workspace enumeration is still too fail-fast for real-world folders

### Evidence

`LiveWorkspaceEnumerator.makeNodes(in:)`:

- recursively walks everything
- throws on nested read failures
- does not define an explicit policy for hidden folders, packages, or provider metadata directories

### Why it matters

One bad descendant can still fail the whole workspace refresh.

That is a poor match for real user folders, which often contain:

- hidden metadata
- package-like folders
- provider-owned entries
- permission edges at arbitrary depths

The tree-browser UI is now good enough that users will notice refresh failures more sharply than before.

### Recommendation

Define a real enumeration policy:

- skip unreadable descendants and log them
- continue building a partial snapshot unless the root itself is unreadable
- decide whether hidden/package/metadata-like folders should be shown, skipped, or opt-in
- add metrics/logging so you know what is being skipped on device

### Suggested tests

- unreadable nested folder should not fail the whole workspace
- hidden/provider subtree fixture
- package-like directory fixture if you plan to support mixed content workspaces

---

## P2 — Direct non-atomic document writes are still a trust tradeoff that needs to be explicitly owned

### Evidence

`PlainTextDocumentSession.writeUTF8Text(...)` still uses:

- direct UTF-8 encoding
- `data.write(to: url, options: [])`

and the comment explicitly says the app is intentionally avoiding an extra atomic replace step.

### Why it matters

This may indeed be the right provider-friendly choice, but it is still a trust boundary.

For a file editor, the write strategy is not an implementation detail. It is a product decision about:

- durability
- provider compatibility
- corruption risk
- recovery expectations after interrupted writes

### Recommendation

Promote this from “comment in one function” to an explicit architecture decision.

Document and choose one path:

- keep direct writes and add corruption-detection / retry / recovery policy, or
- adopt safer atomic replacement where provider behavior allows it

Either choice can be reasonable. The important thing is to make it deliberate.

### Suggested tests / QA

- save under device/background pressure
- provider-backed save QA on iCloud Drive and at least one third-party Files provider
- interrupted save / rapid repeated save scenarios

---

## P2 — File-operation UI state can get stuck if task cancellation happens at the wrong time

### Evidence

`WorkspaceViewModel.startFileOperation(_:)` sets `isPerformingFileOperation = true`, launches a task, and only clears the flag at the end if the task is not cancelled.

There is no `defer` to guarantee the busy state resets.

### Why it matters

This is not the highest-risk bug today, but it is the kind of lifecycle leak that becomes painful once you add:

- more workspace actions
- richer dialogs
- drag/drop or share actions
- retry flows

A stuck “busy” flag can silently block the browser UX in ways that are hard to reproduce.

### Recommendation

Use `defer` around task-owned state mutations for both:

- busy flags
- temporary prompt state that must always unwind

Also audit `loadTask` / `fileOperationTask` patterns for the same shape elsewhere.

### Suggested tests

- cancel an in-flight mutation task and assert the UI leaves busy state
- queue back-to-back operations and assert the second is not permanently blocked

---

## P3 — The codebase still contains some legacy navigation and styling leftovers from before the tree-browser change

### Evidence

- `AppRoute.folder` still exists in the live route model
- `WorkspaceRouteDestination` still supports `.folder(...)`
- several smoke tests still seed folder routes into `session.path`
- `WorkspaceRowView.isSelected` is still passed around but no longer affects the row appearance

### Why it matters

This is not breaking the app today, but it increases review noise and makes future navigation refactors harder because the codebase no longer has one clean source of truth for “what browsing means now.”

### Recommendation

Do a small cleanup pass:

- remove unused folder-route behavior from live code if it is no longer part of the product
- update smoke tests to reflect the inline-tree model instead of old folder navigation assumptions
- remove unused row selection styling inputs if they are truly dead

---

## Strengths worth preserving

These are the things I would actively protect during future work:

1. `EditorViewModel` save acknowledgement merge logic
2. canonical relative-path identity for persistence and reconciliation
3. coordinated workspace mutation boundary in `LiveWorkspaceManager`
4. the current amount of test coverage around restore, rename/delete, autosave, and conflicts
5. keeping file-system semantics out of SwiftUI views

---

## Recommended priority order

1. split compact path history from regular detail selection
2. raise refresh-generation protection to the coordinator/application boundary
3. harden the editor inset bridge and add targeted QA / smoke coverage
4. reduce observation fallback churn
5. define partial-snapshot enumeration policy
6. make the document write-durability decision explicit in architecture/docs/tests
7. clean up legacy folder-route and unused row-state leftovers

---

## Release readiness call

I would call the current codebase:

- **good foundation**
- **safe to keep iterating on**
- **not fully hardened for bigger future feature work yet**

The next step should not be a flashy feature. It should be one focused hardening release that cleans up navigation state ownership, editor bridge ownership, refresh/observation policy, and file-boundary decisions.
