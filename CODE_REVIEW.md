# CODE_REVIEW.md

## Scope

This review reflects the current `Downward.zip` codebase after the recent browser/open-identity regression was fixed.

This was a **static review** of the repository and test suite in this environment. I could inspect the code and tests thoroughly, but I could **not** run `xcodebuild` here, so this should be treated as a code-and-design review rather than a runtime-certified release sign-off.

---

## Executive summary

The codebase is now in a **good, buildable, future-feature-capable state**.

It no longer reads like a fragile prototype. The app has:

- a visible architectural split between `App`, `Domain`, `Features`, `Infrastructure`, and `Shared`,
- explicit workspace and navigation policies,
- a strong test suite around restore, access, enumeration, conflicts, autosave, recents, search, and navigation,
- clearer separation between browser/search presentation and document/file-system boundaries,
- a trusted relative-path model that is finally used in the browser/search open flow.

The recent regression around file opening appears to have been addressed in the right place: the app now treats **workspace-relative identity** as the primary editor identity for browser/search opens, rather than repeatedly re-deriving identity from whichever live URL happened to be tapped.

This does **not** mean the architecture is “finished.” The biggest remaining risks are now **maintainability and scale**, not immediate correctness:

- `AppCoordinator.swift` is still a large pressure point.
- `WorkspaceManager.swift` and `PlainTextDocumentSession.swift` are still dense ownership boundaries.
- The repository docs had drifted into a “historical hardening ledger” and needed to be turned back into active steering documents.

That is a much healthier place to be.

---

## What looks strong now

### 1. Workspace trust model is materially stronger

The code now has a real workspace-boundary policy rather than diffuse path assumptions. `WorkspaceRelativePath` explicitly rejects redirected descendants and validates containment before relative identity is trusted. The enumerator aligns with that policy by skipping redirected descendants rather than surfacing them casually.

### 2. Browser/search open identity is better aligned with the product model

The browser and search flows now carry **trusted relative-path identity** into editor presentation instead of relying purely on URL re-derivation at tap time. That was the right direction after the “Document Unavailable” regression.

### 3. Navigation state is more intentional than earlier versions

The app now distinguishes compact stack navigation from regular-detail selection more clearly. That is especially important on iPad, where the browser is no longer a folder-route drill-down UI.

### 4. Search presentation is more honest

Search rows no longer pretend to be tree rows. Showing filename plus path context is a good product correction and avoids ambiguity when duplicate filenames exist.

### 5. The test suite covers real risks

This repository has a meaningfully broad suite. It is not just testing trivial stores. The tests suggest the architecture is being exercised where it matters: workspace restore, security scope, document lifecycle, autosave/conflict behavior, navigation mode, recents, search, and browser state.

---

## Highest-confidence remaining concerns

### High — `AppCoordinator.swift` is still the main policy pressure point

**Affected area:** `Downward/App/AppCoordinator.swift`

Even after the policy extraction work, the coordinator is still very large and still owns many transitions:

- restore/reconnect,
- editor presentation,
- workspace refresh application,
- mutation result application,
- revalidation routing,
- error escalation,
- restorable-session persistence.

That is still acceptable today, but it is the first place likely to become painful as you add richer editor features, more workspace operations, or more nuanced restore/navigation behavior.

**Recommendation:** Do not rewrite it now. Keep future work disciplined: every time a new rule lands here, ask whether it belongs in `WorkspaceNavigationPolicy`, `WorkspaceSessionPolicy`, or another small policy seam first.

### High — `PlainTextDocumentSession.swift` is still carrying too much behavior in one file

**Affected area:** `Downward/Domain/Document/PlainTextDocumentSession.swift`

The current file still owns a lot:

- open/reload/revalidate,
- write coordination,
- digest/version handling,
- live observation,
- fallback observation,
- conflict mapping,
- relocation,
- logging/diagnostics,
- read/write task helpers.

That is a valid boundary for now, but it is also the file most likely to regress when you add richer editor behaviors.

**Recommendation:** Keep new editor features out of this file unless they are truly file-session responsibilities. UI/editor behaviors should keep living in `EditorViewModel` or dedicated helper seams when possible.

### Medium — The repo still carries “URL fallback” affordances that should stay secondary

**Affected areas:** `WorkspaceViewModel`, `AppCoordinator`, `DocumentManager`

The recent regression showed exactly why raw URL identity is fragile on iOS/iPadOS/provider-backed files. The code now has a better relative-path-first browser flow, but URL-based fallbacks still exist for compatibility and non-browser paths.

That is fine, but the architecture docs should make it explicit that:

- browser/search/recent-file opens should prefer trusted relative-path identity,
- URL-only open paths are a fallback or compatibility lane,
- any future code that starts from the browser tree should not regress to URL-first identity.

### Medium — The docs had become history-heavy rather than roadmap-heavy

**Affected areas:** `TASKS.md`, `PLANS.md`, `QA_CHECKLIST.md`, `TECH_DEBT.md`

The current docs over-emphasized completed hardening work. That is useful as historical record, but not as active steering. The repo now needs docs that answer:

- what is the next work,
- what must not regress,
- where future contributors should extend the code,
- what still counts as intentional debt.

### Medium — Search recomputation ownership is better, but still simple by design

**Affected areas:** `WorkspaceViewModel`, `WorkspaceSearchEngine`, `WorkspaceSnapshot`

This is not a problem now. It is simply a limit worth keeping visible. The app still uses a whole-snapshot model and direct filename/path search. That is fine for the current product, but future content search or very large workspaces should not be stacked on top without an explicit scaling discussion.

### Low — Some preview/test support still depends on URL-shaped sample identity

**Affected areas:** preview support and some stub helpers

The production app is now more relative-path aware than some preview/test seams. This is not an urgent problem, but it is worth keeping preview/sample data aligned with the same identity model over time so regressions become easier to catch visually.

---

## Bottom-line verdict

**Yes, the codebase is robust enough to build on again.**

The main trust and state issues that previously made feature work dangerous have been addressed well enough that the project can return to product work.

The right mindset now is:

- **do not reopen the hardening work casually**,
- **preserve the current invariants**,
- **keep future changes out of the largest pressure-point files unless they truly belong there**,
- **let the docs steer feature work rather than repeating emergency hardening passes**.
