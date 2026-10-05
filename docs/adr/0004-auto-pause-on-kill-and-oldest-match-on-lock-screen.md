# ADR-0004: Auto-pause is detected on relaunch; the lock screen shows the oldest live match

**Date:** 2026-10-05
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
Spec review found two places where the model didn't fit iOS:
- **S27** assumed the app is told when it is terminated. iOS usually kills a suspended app (swiped away, memory pressure) without warning, and a dying phone or a crash gives no signal either. The pause cannot happen at the moment of death.
- **S47** showed "the most recently touched live match". With several live matches, the lock screen would jump between them as each is scored.

## Decision
- **S27:** the kill is detected on the next launch: the last session ended without a clean return to the foreground. Each running live match is then auto-paused, stamped:
  - if the app was in the background when it died: at the time it last went to the background (cleared on every return to the foreground)
  - if it was on screen: at the time of that match's last action
  Already-paused matches are untouched. This runs before the stale check (S28) on the same launch. Backgrounding and locking still never pause.
- **S47:** exactly one Live Activity, for the oldest live match (earliest start; ties by creation order, as `findLive`). Later matches don't appear on the lock screen while it is live. When it finishes, is abandoned or is cancelled, the activity moves to the next-oldest live match, or is removed if none is left.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| CHANGED | 27 | Auto-pause when the app is killed | Trigger: launch after a kill (was: termination signal). `MatchAutoPaused` is stamped with the background time, or the last-action time if the app was on screen. Failure path "phone dies → S28" folded in. |
| CHANGED | 47 | Live match on the lock screen | One activity for the oldest live match (was: most recently touched); hands over to the next-oldest when it ends |

- Events: none added or removed. `MatchAutoPaused` carries a pause time that may be earlier than when it is raised.
- Aggregates: none added. Actors: none added.
- Open questions: none added; Q4 still deferred.

## Consequences
- Requirements: `AutoPauseLiveMatches` triggers on launch (kill detected), not termination; it needs the last background time from the lifecycle adapter. `LockScreenState` selects the oldest live match. `MatchStarted` is listed as a Live Activity trigger (already in the model; missing from requirements).
- S28 needs no change: its idle time measures from the stamped pause.
- Alternatives rejected: a heartbeat timestamp while on screen (accurate, but another moving part); leaving the kill to S28 (match runs on for up to 6 h); one Live Activity per live match (hits iOS's activity limit and clutters the lock screen).
