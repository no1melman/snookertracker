---
status: complete
created: 2026-10-05
priority: critical
tags:
- matches
- domain
- event-sourcing
depends_on:
- '3'
parent: '1'
created_at: 2026-10-05T10:42:31.456414Z
updated_at: 2026-10-05T21:11:50.884457Z
completed_at: 2026-10-05T21:11:50.884457Z
transitions:
- status: in-progress
  at: 2026-10-05T19:18:17.239392Z
- status: complete
  at: 2026-10-05T21:11:50.884457Z
---

# Match aggregate: live play

## Overview
The event-sourced `Match` aggregate for live play, from starting a match to scoring it. Source: `docs/ddd-requirements.md` › Matches › Match › Aggregate and Domain Events. Scenarios S1, S2, S4–S8, S15, S16, S27, S41, S46, S47.

## Requirements
- [x] First: record the event-sourcing decision as an ADR (closes **Q6**) in `docs/adr/` and mark Q6 resolved in `docs/domain/decisions.md`
- [x] `Match.start(setup, at:)`: players distinct, targets valid. Starts in AwaitingBreaker at 0–0, with the match and frame-1 timers starting at `at`. Raises `MatchStarted` (incl. Setup, start time).
- [x] `chooseBreaker(side)`: AwaitingBreaker and not paused → InPlay. Raises `BreakerChosen`.
- [x] `correctBreaker(side)`: live; resets the break-rule origin. Raises `BreakerCorrected`.
- [x] `awardFrame(side, at:)`: InPlay. Frame length is frame start → at, minus paused time. Raises `FrameWon`. Raises `SetWon` on a set target. On the match target → AwaitingConfirmation and raises `MatchTargetReached`.
- [x] `removeFrame(side)`: needs ≥ 1 frame for that side, in InPlay or AwaitingConfirmation. Removes that side's most recent frame and never touches timers. Reverts any set win it caused. AwaitingConfirmation → InPlay. Raises `FrameRemoved`.
- [x] `pause(at:)` and `autoPause(at:)`: allowed in AwaitingBreaker or InPlay. Raise `MatchPaused` and `MatchAutoPaused`.
  - `autoPause(at:)` takes a supplied pause time, which may be earlier than now but never before the last recorded action; the event is stamped with `at` (ADR-0004, ADR-0005)
- [x] `resume(at:)`: Paused → InPlay, or → AwaitingBreaker if there is no breaker yet. Raises `MatchResumed`.
- [x] `overrideColour(side)`: AwaitingBreaker, and both sides share a colour. Gives one side a random different colour for this match only. Raises `MatchColourOverridden`.
- [x] Invariant: the sides are different players
- [x] Invariant: the next breaker is derived.
  - Alternate: the origin breaks odd frames counted from the origin.
  - Winner breaks: the last remaining frame's winner, else the origin.
  - Sets don't affect it.
- [x] Invariant: while Paused, only resume, finish, abandon, cancel and correctBreaker are allowed
- [x] The state rebuilds from its event stream (apply/rehydrate)

## Non-goals
- Ending, stale handling, corrections and deletion (spec: match ending and corrections)
- Persistence (spec: match event store)
- Q3 and Q4: + during a prompt, simultaneous lock-screen and in-app actions (decide in the use-case specs)

## Acceptance criteria
- Domain unit tests cover each behaviour and guard, plus:
  - Breaker derivation: alternate, winner breaks, after −, after correction, across sets
  - Frame length minus paused time
  - − leaves timers alone
  - A set win and its revert
  - Scoring refused while paused
  - `autoPause` refuses a time before the last action

**Implementation skills:** `ddd-tactical-patterns`, `ddd-event-sourcing`, `ddd-domain-events` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):** `Match` in `ios/Sources/Matches/Domain/Match.swift` is an immutable, event-sourced struct. Each behaviour returns `Result<Match, MatchError>` and adds to `uncommittedEvents`. `applying(_:)` is the only thing that changes state, and `rehydrate` replays the history. Tests in `ios/Tests/Matches/DomainTests/MatchLivePlayTests.swift` cover every acceptance item, including encode/decode/rebuild.
- **Decisions:**
  - `start` takes the players' current colours from the caller, and `overrideColour` takes the random colour from the caller, so the domain stays deterministic.
  - `correctBreaker` is allowed in InPlay and Paused, and refused in AwaitingConfirmation and before a breaker exists (`theBreakerCannotBeCorrectedWhileAwaitingConfirmation`).
  - Q3 (+ while the Finish/Continue prompt shows): `awardFrame` is refused in AwaitingConfirmation, so + is disabled until Finish or Undo.
  - Set wins and scores come from a pure `Tally` over the frame list, so removing a frame reverts its set win.
- **Done:** event-sourcing ADR recorded as ADR-0006; Q6 resolved.
