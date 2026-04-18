# PLANS.md

## Current stage

Downward is in a **stable, feature-capable hardening-afterglow stage**.

The codebase no longer looks like a rescue project. It now has:

- a strict workspace trust boundary,
- relative-path-first browser/search/recent-file identity,
- a coherent restore and reconnect model,
- create/rename/delete flows that reconcile browser and editor state,
- editor appearance settings that already ship,
- recent files and pull-to-refresh already integrated into the product.

That changes the planning posture.

The next plan should optimize for:

1. **maintainability before more complexity**,
2. **scale honesty without premature redesign**,
3. **safe user-visible polish**,
4. **keeping docs and tests aligned with the code that actually ships**.

---

## What the review says now

### Strong foundation

The codebase is in good shape to continue building on.

The strongest parts of the current repo are:

- the workspace/document trust model,
- the explicit navigation/session policy seams,
- the breadth of the test suite,
- the decision to keep browser-driven opens relative-path-first,
- the discipline around save/revalidate behavior.

### Main risks are no longer correctness-first

The biggest remaining concerns are now:

- very large pressure-point files,
- one oversized smoke-test suite,
- repeated whole-tree path resolution in some hot paths,
- the risk of identity logic drifting back into multiple nearly-duplicate implementations,
- the temptation to resume feature work by growing the largest files inline.

That is a far healthier set of risks than the repo had before.

---

## Phase 1 — Strengthen maintainability without changing product behavior

### 1.1 Split the smoke-test suite into focused suites

The current test coverage is a strength, but `MarkdownWorkspaceAppSmokeTests.swift` has become too large.

The plan should be to keep the same real behavior coverage while splitting it into smaller feature-oriented suites. The remaining true smoke tests should cover only the cross-feature flows that actually need end-to-end style protection.

### 1.2 Remove repeated whole-snapshot path lookup from search and recents

The clearest near-term scale issue in the current code is repeated recursive relative-path lookup over the same snapshot.

This should be tightened before larger workspaces or richer browser features make the cost more visible. The goal is not a redesign. The goal is to carry already-known relative paths during traversal instead of re-deriving them over and over.

### 1.3 Tighten the ownership story for relative-path derivation

The architecture now has the right identity model, but the implementation still spreads path derivation across multiple layers.

The plan here is not to force everything into one utility type. It is to make the boundaries explicit:

- strict file-system trust validation,
- snapshot-backed path resolution,
- browser presentation path construction,
- route/document reconciliation.

This is the most important maintainability protection against another open-identity regression.

---

## Phase 2 — Resume visible product work carefully

### 2.1 Editor polish should be the first major user-visible lane

The foundation is now strong enough that editor polish is a sensible next feature area.

Good editor work from this point forward should:

- stay above the current document session boundary,
- preserve quiet autosave,
- preserve calm revalidation,
- preserve exceptional-only conflict UI.

This is where the product is most likely to gain visible value without forcing an architectural restart.

### 2.2 Browser polish should stay presentation-first

The browser is now structurally correct enough to improve, but future work should stay disciplined.

Improvements should focus on scanability, metadata, recents/search workflow, and faster browsing. They should not reintroduce URL-first open logic or a second competing browser architecture.

### 2.3 Settings are now a maintained surface, not a planned feature

Editor appearance settings already exist.

That means future planning should treat settings as a real product surface that needs:

- accurate docs,
- normalization and persistence tests kept current,
- disciplined additions through the existing store and settings screen.

The plan should no longer describe font settings as unfinished roadmap work.

---

## Phase 3 — Keep pressure points healthy

### 3.1 `AppCoordinator` should continue losing policy, not gaining it

Do not rewrite `AppCoordinator` right now.

Instead, keep using this decision rule:

- navigation transforms belong in `WorkspaceNavigationPolicy`,
- workspace-state application and refresh reconciliation belong in `WorkspaceSessionPolicy`,
- editor-local behavior belongs in `EditorViewModel` or the document layer,
- only cross-boundary orchestration belongs inline in the coordinator.

### 3.2 `PlainTextDocumentSession` should stay narrow and file-session-specific

The document session is still dense, but it is also doing important work correctly.

Do not split it speculatively. Protect it by refusing to put non-session editor features into it. When a real seam becomes obvious, split only that seam.

### 3.3 Keep giant files from becoming architecture again

There are a few files where size is now the warning sign:

- `AppCoordinator.swift`
- `PlainTextDocumentSession.swift`
- `WorkspaceManager.swift`
- `WorkspaceViewModel.swift`
- the smoke-test suite

The plan is not to make everything tiny. It is to avoid a future where all interesting behavior once again funnels into the biggest file available.

---

## Phase 4 — Be honest about the current scale boundary

## Current model that is still valid

The app still intentionally uses:

- one selected workspace,
- one whole `WorkspaceSnapshot`,
- one live editor document/session at a time,
- filename/path search over the in-memory snapshot,
- whole-snapshot refresh and mutation reconciliation.

That is still a valid product model for Downward today.

## What should trigger a real design pass

Treat these as design-level triggers, not incidental feature additions:

- content search,
- very large workspaces where search or pruning starts to feel expensive,
- multi-pane or multi-window editing,
- multiple simultaneous live document sessions,
- much richer restore/history behavior,
- background synchronization features that need more than whole-snapshot replacement.

When one of those becomes a real near-term goal, do a design pass first. Do not stretch the current model silently.

---

## Practical next sequence

1. Split the giant smoke-test file while preserving behavior coverage.
2. Remove repeated whole-tree path lookup from search and recent-file pruning.
3. Tighten and document the relative-path derivation seams.
4. Resume user-visible editor polish.
5. Continue browser polish without regressing relative-path-first identity.
6. Keep docs and tests truthful as the product evolves.

That is the right plan for the current codebase: **preserve the hard-won boundaries, improve maintainability where the code is starting to strain, then ship visible value carefully.**
