# TASKS.md

## Purpose

This file is the active backlog and steering summary for Downward.
It intentionally stays short. Use `PLANS.md` for the detailed technical checklist, performance roadmap, and code-review findings behind this backlog.

---

## Current state

The repo is no longer in emergency hardening mode.
The strongest current foundations are:

- the workspace trust boundary,
- relative-path-first open identity,
- restore and reconnect behavior,
- quiet autosave, explicit autosave cancellation, and calmer revalidation,
- a split app-level test stack with a short smoke suite plus focused restore, mutation, and trusted-open/recent suites,
- explicit keyboard-safe-area underlap for the editor,
- seamless top editor underlay with a shared safe-area-driven first-line inset, an outer-geometry top-clearance source, and explicit document-open viewport reset,
- a shared resolved editor theme pipeline for renderer colors, TextKit backgrounds, and a painted keyboard accessory underlay that matches the editor surface,
- a split editor bridge where the representable, coordinator, accessory view, keyboard geometry, and `UITextView` subclass now live in focused files,
- a bounded current-line restyle path so ordinary same-line markdown edits no longer automatically fall back to whole-document rerenders,
- an explicit markdown syntax visibility contract for future renderer work,
- a maintained prototype-aligned settings sheet with a native inset-grouped home list, nested Editor/Theme/Markdown/Tips/Information/About pages, persisted theme selection, custom-theme persistence, and honest placeholders for unfinished StoreKit/legal/rating areas,
- workspace-visible `.json` files that open in the editor like other supported text files, while theme import remains an explicit Theme settings action,
- a clearer app-coordinator boundary where workspace selection/refresh session application now flows through `WorkspaceSessionPolicy`, mutation preflight and browser-kind rules live in `WorkspaceMutationPolicy`, mutation execution metadata lives in `WorkspaceMutationService`, and trusted route/recent-file decisions live in `WorkspaceNavigationPolicy`,
- leaner document-session version bookkeeping where open/reload hash raw file bytes and save/autosave reuse the exact UTF-8 payload being written,
- an async lifecycle audit that keeps workspace refresh/mutation application generation-gated and makes delayed editor conflict-resolution tasks cancel/identity-check before applying results,
- recent files, app appearance, and editor appearance persistence, including monospaced and proportional editor font choices,
- a broad test suite around risky behaviors.

The main risks now are **maintainability**, **broader large-file rendering work**, **renderer/theme extensibility**, and **real-device UI polish**, not basic correctness. Async lifecycle ownership is in better shape after the audit, but new unstructured tasks still need explicit ownership and stale-result guards. The main editor-specific risks are still real-device verification of initial first-line placement on iPhone/iPad and of the shared theme/accessory pipeline on non-standard backgrounds; the settings hierarchy and initial custom theme management are now real, but StoreKit tips, legal/rating URLs, and richer theme-schema validation are still future work.

---

## Current guardrails

These are not backlog items. They are shipping expectations.

- Browser, search, and recent-file opens should stay relative-path-first whenever that identity is already known.
- Final file-system operations must still validate against the chosen workspace root.
- Redirected descendants must not re-enter the browser or document pipeline.
- The app still owns one active live document session at a time.
- Autosave should remain quiet.
- Conflict UI should remain exceptional.
- Refreshes and mutations must continue to reconcile under one explicit winner policy.
- Async work that can mutate state after suspension must be owned by a session/model boundary and guarded by cancellation, generation, or workspace/document identity.
- Settings and editor polish must not push unrelated logic into Views or into `PlainTextDocumentSession`.

---

## Highest-priority work

### 1. Keep `AppCoordinator` from regaining feature logic

**Why**

`AppCoordinator.swift` is still the easiest place for “just one more rule” to accumulate.

**Success**

- new navigation rules land in `WorkspaceNavigationPolicy`,
- workspace-state application rules land in `WorkspaceSessionPolicy`,
- repeated mutation execution, preflight, or error rules land in focused mutation seams instead of new inline coordinator branches,
- the coordinator stays an orchestrator instead of becoming the architecture.

### 2. Protect `PlainTextDocumentSession` and the renderer from feature creep

**Why**

`PlainTextDocumentSession.swift` and `MarkdownStyledTextRenderer.swift` are both real boundaries and easy places to overstuff. Future markdown and JSON theme work will be much easier if parsing, styling, theme roles, and TextKit layout behavior stay separate.

**Success**

- session code stays focused on file truth,
- rendering code stays focused on markdown presentation,
- syntax recognition is separated from theme/style application before major new markdown features land,
- future markdown work extends the explicit mode-controlled vs always-hidden syntax contract instead of inventing new visibility paths,
- hidden syntax remains glyph-level layout behavior rather than font/kerning tricks,
- new editor UX does not automatically land in either file.

### 3. Finish production polish around Settings and theme management

**Why**

The settings hierarchy is now a real product surface, including Theme and New Theme screens. Built-in theme selection, custom theme persistence, and JSON import/export now have backing infrastructure; future work should refine that hierarchy instead of replacing it.

**Success**

- harden and polish the initial persisted theme management flow,
- keep explicit theme imports routed through `ThemeImportService`/`ThemeStore`, not through document editing,
- keep settings as a sheet over the current workspace/editor on both compact and regular layouts,
- preserve the existing working workspace/editor/markdown controls,
- keep StoreKit and legal/rating links honest until the backing infrastructure actually ships,
- add richer theme-schema validation and migration support before expanding the import format further.

**Likely files**

- `Downward/Features/Settings/SettingsScreen.swift`
- future dedicated theme settings views if needed

---

## Secondary cleanup

### 5. Keep preview and sample data aligned with the real product model

Preview and sample identity should stay close to the same relative-path-first model used in production so visual testing stays useful.

### 6. Keep docs truthful

Any editor, navigation, or settings change should be reflected in:

- `AGENTS.md` when it changes a hard rule,
- `ARCHITECTURE.md` when it changes ownership,
- `TASKS.md` when it changes active priorities or known pressure points.

---

## Intentional debt that is acceptable for now

- `AppCoordinator.swift` is still large, but refresh application, replacement selection, trusted route/recent-file decisions, and repeated mutation execution/error paths no longer need to grow inline there.
- `PlainTextDocumentSession.swift` is still dense, but it is currently the right file-session boundary and its version bookkeeping no longer needs extra whole-buffer UTF-8 round-trips on open/save.
- The app still uses one whole workspace snapshot and simple filename/path search.
- URL-only open paths still exist for compatibility, but should stay secondary.

---

## Explicit non-goals right now

Do not start these without a design pass first:

- content search,
- a second editor implementation,
- multi-window or multi-pane live editing,
- an app-owned mirrored document store,
- large-scale architecture rewrites without a concrete product need.
