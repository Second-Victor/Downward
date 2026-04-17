# PLANS.md

## Current stage

Downward has completed its main **correctness and hardening stage**.

The project should now move in a different mode:

- preserve the file-safety and state-consistency boundaries already earned,
- grow the product in small, deliberate passes,
- avoid reopening the old emergency-hardening loop unless a new regression proves it is necessary.

---

## What changed since the last plan

The repo is no longer primarily about:

- fixing workspace containment,
- fixing refresh-vs-mutation winner rules,
- fixing cancellation on read-side I/O,
- repairing compact vs regular navigation,
- repairing browser/search open identity.

Those areas now form the **current foundation**.

The new plan should therefore optimize for:

1. **safe feature velocity**,
2. **pressure-point discipline**,
3. **explicit scaling limits**,
4. **keeping the docs and tests truthful as the product grows**.

---

## Phase 1 — Protect the current foundation

### 1.1 Lock in browser/search open identity

The most recent serious regression was the file-open break caused by mixed URL identity and trusted relative identity.

Before broader feature work, add one explicit regression pass so the following stays impossible to break casually:

- tree row open,
- search result open,
- regular-detail pending presentation,
- trusted relative-path document loading.

### 1.2 Keep the “allowed `Task.detached`” rule explicit

The repo now appears to reserve detached tasks for write/mutation work that should outlive transient caller cancellation.
That is a good rule.
It should remain visible in code comments and tests.

### 1.3 Keep docs active, not historical

Do not let `TASKS.md` and `PLANS.md` turn back into a ledger of already-completed emergency fixes.
They should keep steering the next real work.

---

## Phase 2 — Resume product work safely

### 2.1 Settings and editor polish

The codebase is stable enough for more settings and editor improvements.
These are good next feature areas because they add visible value without forcing an immediate redesign.

Conditions:

- no regression in autosave calmness,
- no regression in conflict presentation,
- no new global state routing through `AppCoordinator` unless it truly belongs there.

### 2.2 Browser polish and workflow improvements

The inline tree model is now the right product direction.
Future browser work should focus on:

- faster workflow,
- better metadata and row affordances,
- stronger recents/search integration,
- without regressing trusted relative-path identity.

### 2.3 Search improvements, still within the simple model

Filename/path search is good enough today.
Add improvements only while the current whole-snapshot model still feels natural.
When that stops being true, treat that as a design milestone, not an incidental refactor.

---

## Phase 3 — Manage the known pressure points

### 3.1 Coordinator discipline

`AppCoordinator` is still a large file.
Do not rewrite it now.
Instead, use this decision rule:

- if a new rule is specific to navigation state, prefer `WorkspaceNavigationPolicy`,
- if a new rule is specific to applying/reconciling workspace state, prefer `WorkspaceSessionPolicy`,
- if a new rule is editor-local, prefer `EditorViewModel` or document-layer ownership,
- only keep logic inline in the coordinator when it is truly orchestration.

### 3.2 Document-session discipline

`PlainTextDocumentSession` is still dense.
Future work should protect it by keeping non-file-session concerns out of it.

A split should happen only when a real seam is obvious, such as:

- observation policy,
- coordinated read/write helpers,
- conflict mapping,
- diagnostics.

### 3.3 View-model discipline

`WorkspaceViewModel` and `EditorViewModel` are both meaningful product seams now.
Use them for presentation behavior, not as dumping grounds for new domain logic.

---

## Phase 4 — Be explicit about scale limits

## Whole-snapshot model

The current workspace model is still:

- one `WorkspaceSnapshot`,
- whole-tree replacement on refresh/mutation application,
- direct filename/path search over the current snapshot,
- one live editor document/session at a time.

That is a valid model for the current product.
It is also the key scaling boundary.

### What should trigger a design revisit

Treat the following as signals that the app is approaching the edge of the current model:

- content search,
- very large workspaces with slow snapshot churn,
- multi-pane or multi-window editing,
- richer live browser synchronization,
- more advanced recent-file/session restoration behavior.

When one of those becomes a real near-term feature, plan a design pass first.
Do not try to stretch the current model silently.

---

## Practical next sequence

1. Add one explicit regression pass for browser/search/document open identity.
2. Start the next user-visible feature pass in settings or editor polish.
3. Keep browser polish relative-path-first.
4. Refuse opportunistic complexity inside the largest files.
5. Revisit architecture only when a real feature forces a boundary change.

That is the right balance for the current repo: **protect what was hardened, then ship visible value carefully.**
