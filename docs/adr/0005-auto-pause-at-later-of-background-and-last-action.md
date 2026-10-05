# ADR-0005: Auto-pause at the later of the background time and the last action

**Date:** 2026-10-05
**Status:** Accepted
**Supersedes:** — (refines ADR-0004's S27 pause time)   **Superseded by:** —

## Context
ADR-0004 pauses a killed app's matches at the time it last went to the background. But the lock-screen buttons (S47) work while the app is in the background, so a frame can be scored after that time. Pausing at the background time would put the pause before that frame (Q7).

## Decision
- **S27:** each running live match is auto-paused at the **later** of the app's last background time and that match's last action. With no background time recorded (the app was on screen when it died), that is the last action, as before.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| CHANGED | 27 | Auto-pause when the app is killed | Pause time = max(last background time, match's last action) |

- Events, aggregates, actors: none added or removed.
- Open questions: Q7 resolved.

## Consequences
- Requirements: `AutoPauseLiveMatches` computes the pause time per match; `autoPause(at:)` can guard that `at` is not earlier than the last action.
- The auto-pause stamp never precedes a recorded action, so the match history stays in time order.
