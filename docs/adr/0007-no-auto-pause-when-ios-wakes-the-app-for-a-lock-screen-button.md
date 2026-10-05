# ADR-0007: No auto-pause when iOS wakes the app for a lock-screen button

**Date:** 2026-10-05
**Status:** Accepted
**Supersedes:** —   **Superseded by:** — (refines ADR-0004 and ADR-0005's S27 trigger)

## Context
ADR-0004 detects a kill on the next launch: any new process means the previous one died. iOS also reclaims suspended apps on its own, which is common while the phone lies locked on the rail. When the scorer then taps a lock-screen button (S47), iOS starts the app **in the background** to run it. Under ADR-0004 that launch counted as a kill, so the match was auto-paused first and the + was then refused because the match was paused. The lock-screen buttons would fail exactly when they are needed.

## Decision
- **S27:** a launch that iOS makes in the background (the app is not on screen) is not treated as a kill. Nothing is auto-paused, and the last background time is kept, because the app is still in the background.
- Only a launch onto the screen checks for a kill. The pause time is unchanged from ADR-0005: the later of the last background time and the match's last action, so a lock-screen frame scored in between is never put after the pause.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| CHANGED | 27 | Auto-pause when the app is killed | Trigger: the next launch **onto the screen** after a kill (background launches for S47 buttons are excluded) |

- Events, aggregates, actors: none added or removed.
- Open questions: none added.

## Consequences
- Lock-screen +, pause and resume work after iOS has reclaimed the app.
- A match left running after the scorer deliberately swiped the app away still auto-pauses when the app is next opened, at the later of the background time and any lock-screen action since.
- The lifecycle adapter reports `launchedInBackground` from `UIApplication.applicationState` at launch; `AppLaunchSequence.run(launchedInBackground:)` skips auto-pause for it.
