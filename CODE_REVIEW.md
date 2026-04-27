# CODE_REVIEW.md

## Purpose

This file is a lightweight code-review index for Downward. Active review findings and next-work checklists now live in `PLANS.md`; do not maintain a second active backlog here.

Use this file only for:

- review scope notes,
- high-level architectural observations,
- links from review batches to the active plan,
- historical rationale that is too broad for an individual checklist item.

New actionable findings should be added directly to `PLANS.md`, not to a second task backlog.

## Latest review

Date: 2026-04-26
Scope: static review of the uploaded project archive after the recent code-fix batches.
Build/test status: `xcodebuild -list`, iPhone simulator build, iPad simulator build, and the full iPhone simulator XCTest suite passed during the documentation consolidation pass. See `RELEASE_QA.md` for exact commands and counts.

## Current review summary

The app architecture is directionally sound:

- `AppContainer` composes stores, managers, coordinator, session, and view models cleanly.
- `AppSession` centralizes UI-facing app state rather than scattering it through views.
- `AppCoordinator` remains the orchestration hub, with navigation/session/mutation decisions partially pushed into policy seams.
- `WorkspaceManager`, `WorkspaceRelativePath`, and `WorkspaceSnapshot` preserve the workspace-relative identity model and final file-system validation boundaries.
- `PlainTextDocumentSession` owns document truth, save/reload/revalidation, and live observation rather than pushing file truth into editor views.
- The editor stack uses a SwiftUI-hosted `UITextView` boundary, which is the right direction for the current markdown/editing requirements.
- Markdown rendering has started to split into scanner, visibility policy, style applicator, renderer, and TextKit layout responsibilities.
- Settings/theme persistence has real stores and explicit JSON exchange paths instead of ad hoc view state.
- Test coverage is broad around workspace restore, mutation, recents, autosave, conflict handling, renderer behavior, and settings/theme flows.

The remaining review concerns are now mostly execution risk rather than architectural direction:

- continued release discipline now that the `AppCoordinator.loadDocument(at:)` stale-recent cleanup call has been verified in build/test,
- large boundary files that need protection from unrelated growth,
- renderer scalability for large documents,
- unstructured task ownership and stale-result suppression,
- real-device and Files-provider QA coverage.

## Active findings

See `PLANS.md` for the current P0/P1/P2 checklist. The active plan currently tracks:

- green build restoration,
- manual release QA,
- large boundary file ownership,
- renderer scalability,
- async task ownership,
- workspace mutation and recents coherence,
- keyboard accessory and editor chrome verification,
- theme import/export polish,
- placeholder-backed product surfaces.

## Review process going forward

When doing future reviews:

1. Review architecture boundaries against `ARCHITECTURE.md`.
2. Add actionable findings to `PLANS.md` with priority, context, checklist, and done criteria.
3. Put build/test/manual evidence in `RELEASE_QA.md`.
4. Keep this file as the review index only.
5. Remove completed checklist detail from `PLANS.md` once it stops helping with next-step planning.
