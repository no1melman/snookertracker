---
status: in-progress
created: 2026-10-05
priority: high
tags:
- matches
- application
depends_on:
- '5'
- '6'
- '14'
parent: '1'
created_at: 2026-10-05T10:42:31.503356Z
updated_at: 2026-10-06T19:22:25.877955Z
transitions:
- status: in-progress
  at: 2026-10-06T19:22:25.877955Z
---

# Match use cases: ending, stale & maintenance

## Overview
Command-side use cases for ending, maintaining and cleaning up matches. Source: `docs/ddd-requirements.md` › Matches › Match › Use Cases. Scenarios S10, S15, S16, S25–S31, S37, S43.

## Requirements
- [x] `FinishMatch` (menu + confirmation, or the Finish prompt): an early finish of a target style returns "will be abandoned" unless `anyway`
- [x] `AbandonMatch` and `CancelMatch`, with confirmation
- [x] `FinishAllMatches`: finishable matches are finished, the others abandoned; one dialog if any will be abandoned
- [ ] `AutoPauseLiveMatches` (launch, after a kill; ADR-0004, ADR-0005):
  - Input: the last background time, if recorded
  - `findLive` → `autoPause(at:)` each running match, `at` = the later of the background time and that match's last action (the last action when none was recorded)
  - Already-paused matches untouched; runs before `FlagStaleMatches`
- [x] `FlagStaleMatches`:
  - `findLive`, filtered by idle ≥ 6 h
  - Queries Stats' `AverageFrameTime` and `AverageMatchLength` (3 h fallback)
  - Prompts one match at a time
- [x] `ResolveStaleMatch`: resume, end at a chosen time, end capped, abandon, cancel (S28)
- [x] `WarnLongFrame` (Clock-triggered): define a `NotificationScheduler` port here and test against an in-memory fake; the UserNotifications adapter is in 019. A policy on published match events that schedules OS notifications ahead (the clock is the OS, so it works while suspended); `LongFrameWarned` is not recorded
- [x] `CorrectMatchScore` (timeline → Edit). Q1 and Q2 re-deferred (see Progress).
- [x] `MarkMatchFinished`
- [x] `DeleteMatch` (swipe + confirmation)

## UI (design language: 022)
- [x] The live screen's **⋯ menu**:
  - Finish, Abandon and Cancel, each with a confirmation
  - Finishing a target style early warns "will be abandoned" and offers Finish anyway
- [ ] The **Finish?** and **Continue?** prompts (S15/S16) offer Undo
  - [x] Finish? (target reached): Finish Match / Undo Last Frame
  - [ ] Continue? (set won): blocked — the sets style isn't offered by New Game, and `LiveMatchScreen` has no set-won flag (read model, spec 009)
- [x] A **Finish all** action in the hub's Live section (shown with 2+ live matches), with one dialog that warns when any match will be abandoned
- [x] **Match detail actions** (013):
  - [x] Correct score (Edit from the timeline)
  - [x] Mark finished (abandoned matches only)
  - [x] Delete (swipe on a History row, or the detail's ⋯ menu, with confirmation)
- [x] **Swipe a live match** in the hub's Live section: Finish or Abandon, with the live screen's confirmations (Finish short of the target asks "Finish anyway")
- Swipe actions are icon-only (no caption under the icon)

## Non-goals
- The iOS lifecycle and notification adapters (their own specs)
- The merge and removal policies (in the players spec)

## Acceptance criteria
- One integration test per use case, including:
  - Finish all with mixed matches
  - Auto-pause at the background time, at a later lock-screen action, and at the last action when no background time was recorded
  - Stale prompt order
  - Stale with no history falling back to 3 h

**Implementation skill:** `ddd-application-layer` · **Tests:** `ddd-testing`

## Progress (2026-10-06)
- `DeleteMatch` is in `MatchCommands` / `MatchUseCases`. It loads the match, calls `Match.delete` (ended matches only), saves and publishes `MatchDeleted`. Stats folds that to no record, so the match leaves History and stats. Tests: `MatchesIntegrationTests` (ended → deleted and published; live → refused).
- History gets `DeleteMatch` as a closure on `StatsPorts`, wired in the composition root, so Stats Presentation does not import Matches.
- The live row swipe reuses `LiveMatchView`'s dialog title, button and message, now static.
- `FinishAllMatches` is two calls: `finishAllMatchesPreview()` (counts finishing / abandoning, so the UI shows one dialog) and `finishAllMatches()`. "Short of target" is asked of the domain (`finish` refusing with `finishShortOfTarget`), never recomputed. Each match is its own save; a failure doesn't stop the rest and the first is rethrown.
- `CorrectMatchScore(match, to: CorrectedScore, confirmed:)`: a race-to score off the target throws `correctionNotOnTarget(n)`; a sets inconsistency throws `correctionNeedsConfirmation([warnings])` with nothing saved, and saves when `confirmed`. Cancelled → `notAllowedNow`.
- `MarkMatchFinished`: abandoned only; the leader wins, level is a draw (domain).
- Match detail actions: Stats Presentation defines `MatchDetailActions` (closures: `correctScore` returning the warnings to confirm, `markFinished`, `delete`) with its own `\.matchDetailActions` environment value; nil hides Edit and the ⋯ menu. The composition root adapts `MatchCommands`.
- Q1 (phone dies mid-correction) and Q2 (two corrections in a row) stay **deferred**: the scenarios don't decide them. Defaults as built: a correction is one event, stored whole or not at all; a second correction builds on the first (its frames start from the corrected ones) and each is its own entry in the timeline's Alterations.
- Tests (`MatchesIntegrationTests`): Finish all with mixed matches (most frames, target reached, paused short of target), Finish all with no warning, race-to correction on/off target, two corrections, sets warnings confirmed before saving, cancelled not correctable, mark finished.
- Left for round 2: `AutoPauseLiveMatches` items still unticked here, `FlagStaleMatches`, `ResolveStaleMatch`, `WarnLongFrame`; the Continue? prompt (above).

## Progress (S28, stale matches)
- `FlagStaleMatches` / `ResolveStaleMatch` are `StaleMatchCommands`, built by `StaleMatchUseCases` in `Matches/Application/Stale/`. It reuses `MatchUseCases`' repository and `commit` (both internal), so it saves, publishes and projects like every other command; `MatchUseCases` is unchanged.
- Flag: `findLive` (prompt order = oldest started first) filtered by `isStale` (idle ≥ 6 h). Suggested end = `suggestedStaleEndTime` with Stats' `averageFrameTime` of the last frame's winner (the match's own average when nil). Cap = `averageMatchLength(pair, weekday of the start)`, else 3 h. `StaleMatchFlagged` is stored (not published) on every launch it is flagged; it is not an action, so the idle time keeps growing.
- Resolve: `StaleChoice` (`resume`, `endAt(Date)`, `endCapped`, `abandon`, `cancel`) → `Match.resolveStale`. The cap is recomputed at resolve time. Refusals: `StaleMatchError.endTimeOutOfBounds`, `.noLongerStale` (played or ended since the flag), and `finishShortOfTarget` (ask, then `anyway`).
- Tests: `StaleMatchesTests` (16): prompt order, the 6 h threshold, flag stored not published, 3 h fallback, the weekday cap, the suggested end (Stats and own average), each resolution, out-of-bounds end, short of target, no longer stale, and the queue.
- The prompt and its wiring: spec 020.
