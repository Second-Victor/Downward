# TECH_DEBT.md

## Purpose

This file tracks **intentional, non-blocking debt** in the current Downward codebase.

These items are visible so future contributors do not mistake them for either solved problems or emergency blockers.

---

## 1. Coordinator pressure still exists

`AppCoordinator` is healthier than before, but it is still the main orchestration pressure point.

This is acceptable now.
It becomes debt again only if future work keeps adding policy inline instead of extending existing seams.

---

## 2. `PlainTextDocumentSession` is still a dense ownership boundary

The file is correct enough today, but it remains one of the most delicate places to modify.

This should be revisited only when a real seam becomes worth extracting.

---

## 3. Whole-snapshot browser/search model is intentionally simple

The app still uses:

- one whole workspace snapshot,
- simple filename/path search,
- whole-snapshot replacement/reconciliation.

This is a known scale limit, not an active bug.

---

## 4. URL-only open paths are compatibility paths, not the preferred product model

The app now works best when browser/search/recent-file flows begin from trusted relative-path identity.
Raw URL-based open paths still exist and may remain necessary in a few places, but they should stay secondary.

---

## 5. Preview/sample support needs periodic truth checks

Preview/sample data is useful in this repo, but it can drift after navigation/browser/editor changes.
This is worth small, regular cleanup rather than another large preview overhaul later.
