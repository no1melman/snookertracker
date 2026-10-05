---
status: in-progress
created: 2026-10-05
priority: high
tags:
- matches
- domain
depends_on:
- '4'
parent: '1'
created_at: 2026-10-05T10:42:31.461959Z
updated_at: 2026-10-05T20:21:31.705132Z
transitions:
- status: in-progress
  at: 2026-10-05T20:21:31.705132Z
---

# Match aggregate: ending, stale & corrections

## Overview
`Match` behaviours for ending a match and changing it afterwards. Source: `docs/ddd-requirements.md` › Matches › Match › Aggregate and Domain Events. Scenarios S10, S15, S16, S25, S26, S28–S31, S37, S42, S43.

## Requirements
- [ ] `finish(at:, anyway:)`: live.
  - Most frames wins at any time; level is a draw.
  - Target styles may finish from AwaitingConfirmation. Short of the target, they finish only with `anyway`; otherwise refuse with "will be abandoned".
  - From AwaitingConfirmation, the end time is the winning frame's time.
  - Drops an in-progress frame.
  - Raises `MatchFinished`.
- [ ] `abandon(at:)` and `cancel(at:)`: live. Raise `MatchAbandoned` and `MatchCancelled`.
- [ ] `flagStale(now:)`: live, with the last action ≥ 6 h ago. Takes the suggested end time and capped length as inputs (from the Stats queries). Raises `StaleMatchFlagged` (Stage 1).
- [ ] `resolveStale(StaleResolution)`: delegates to resume, finish (`ChosenEndTime` or `CappedLength`), abandon or cancel
- [ ] `warnLongFrame(now:)`: InPlay, at ≥ 30 min, then every 10 min. Raises `LongFrameWarned`.
- [ ] `correctScore(ScoreCorrection)`: Finished or Abandoned. Recorded as a correction. Raises `MatchScoreCorrected`.
- [ ] `markFinished()`: Abandoned only; the result is the leader or a draw. Raises `MatchMarkedFinished`.
- [ ] `delete()`: Finished, Abandoned or Cancelled. Raises `MatchDeleted`.
- [ ] Invariant: an ended match's original events are never altered; corrections are new events
- [ ] Invariant: only a stale match's length can be capped
- [ ] Invariant: finished never becomes abandoned, and cancelled never changes (except delete)

## Non-goals
- Q1 and Q2 (phone dies mid-correction; two corrections in a row). Revisit during implementation and record the answer through `/ddd delta`.

## Acceptance criteria
- Domain unit tests cover:
  - Early finish of target styles
  - End time = the winning frame's time
  - Draws
  - Stale detection at exactly 6 h
  - Long-frame thresholds at 30 and 10 min
  - Race-to correction validity and sets correction warnings
  - Abandoned → finished only
  - Each refused transition

**Implementation skills:** `ddd-tactical-patterns`, `ddd-domain-events` · **Tests:** `ddd-testing`
