# TECH_DEBT.md

## Non-blocking debt

These items are worth cleaning up, but they should follow the trust/state hardening work.

## 1. Preview realism drift

Some preview/sample data still reflects older browser or row assumptions.
That makes visual iteration less trustworthy than it should be.

## 2. Coordinator pressure is reduced, but still real

`AppCoordinator` is no longer carrying every cross-domain rule inline, but it is still the main policy pressure point for future feature work.
That is acceptable now.
It should stay visible as a maintenance boundary.

## 3. Diagnostics are intentionally lightweight

The app now emits contained diagnostics for some degraded conditions:

- partial enumeration skips,
- fallback observation,
- reconnect-related restore/access paths.

If provider-related debugging grows, the next step should be more structured diagnostics rather than noisier ad hoc logs.

## 4. Whole-tree snapshot model is still the simple version

That is appropriate today.
It should stay visible as a known limit so future contributors do not accidentally stack large-workspace features on top without acknowledging the tradeoff.
