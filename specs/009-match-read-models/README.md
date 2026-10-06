---
status: in-progress
created: 2026-10-05
priority: high
tags:
- matches
- cqrs
depends_on:
- '6'
parent: '1'
created_at: 2026-10-05T10:42:31.480023Z
updated_at: 2026-10-05T20:21:32.214087Z
transitions:
- status: in-progress
  at: 2026-10-05T20:21:32.214087Z
---

# Matches read models & open-host queries

## Overview
Matches query side: live-match views and the open-host queries that Players calls. These bypass the domain model. Source: `docs/ddd-requirements.md` › Matches › Match › Read Requirements.

## Requirements
- [x] `LiveMatches`: match id, players, colours, score, match timer, paused. Oldest started first.
- [ ] `LiveMatchScreen`:
  - Day + time, sides with colours, score (sets format), breaker dot
  - Match timer, frame timer, paused, available controls
  - Head-to-head from Stats' `HeadToHead` OHS (inject the protocol, so it can be stubbed until Stats lands)
- [ ] `LockScreenState`: the oldest live match (as `findLive`), or none: match id, sides, score, breaker, frame timer, paused (Q4 noted). Moves to the next-oldest when the shown match ends (ADR-0004).
- [ ] OHS `IsPlayerInLiveMatch(PlayerId)`: used by Players' archive guard and the "are you sure" check on start
- [ ] OHS `HavePlayedEachOther(PlayerId, PlayerId)`: used by Players' merge guard
- [x] Projections are kept current from the match event stream

## UI (design language: 022)
- [x] The hub's **Live** section, from `LiveMatches`:
  - Oldest first, one row per match: both colour plates and names, the score in monospaced digits, a running match timer, and a Paused label
  - Tapping a row opens the live screen. The section is hidden when there are no live matches.
- [ ] The **live screen**, from `LiveMatchScreen`:
  - Two player columns, each with a colour plate, name and huge frame count; a dot marks the breaker
  - Frame timer, match timer, and day and time are secondary
  - A head-to-head strip underneath, hidden when the players have no history
  - Controls are enabled from "available controls"
- [x] **Paused:** a clear Paused state, timers frozen, and every control except Resume disabled
- [ ] **VoiceOver** reads the score as "Asher 4, Me 3", plus the breaker and the paused state. At accessibility Dynamic Type sizes the score stays legible.

## Non-goals
- Past-match lists and stats (Stats context)

## Acceptance criteria
- One integration test per read requirement, covering ordering, the sets score format, the paused flag and the lock-screen hand-over to the next-oldest live match
- The OHS protocols are published in the module that Players depends on

**Implementation skill:** `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):**
  - `LiveMatchesProjection` (`ios/Sources/Matches/Application/`) serves `LiveMatches` and most of `LiveMatchScreen`: timers, breaker, available controls, and `targetReachedBy` for the Finish/Undo prompt.
  - Players' names are read at query time through `MatchPlayerDirectory`, so a rename shows straight away.
  - UI: `LiveMatchesSection` (hidden when empty) and `LiveMatchView`, with a clear Paused bar where only Resume and the ⋯ end actions stay enabled.
  - Tests: `liveMatchesAreOldestFirstAndShowThePausedFlag` and `scoringAMatchSurvivesARelaunch`.
- **Decisions:** the projection is not folded from events. It is rebuilt at launch from `findLive()` and replaced from the committed aggregate after every save. Finish, Abandon and Cancel stay enabled while paused, because the domain allows them.
- **Remains:**
  - The sets score format on the live screen (the app-layer `MatchStyle` has no sets).
  - The head-to-head (`HeadToHead` OHS) and its strip.
  - `LockScreenState` with the next-oldest hand-over.
  - The `IsPlayerInLiveMatch` and `HavePlayedEachOther` OHS in `MatchesPublished`.
  - VoiceOver reads the live screen per column, not "Asher 4, Me 3". The hub row does read it that way.
  - Integration tests for the sets format and the lock-screen hand-over.
