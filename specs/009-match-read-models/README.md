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
- [ ] `LiveMatches`: match id, players, colours, score, match timer, paused. Oldest started first.
- [ ] `LiveMatchScreen`:
  - Day + time, sides with colours, score (sets format), breaker dot
  - Match timer, frame timer, paused, available controls
  - Head-to-head from Stats' `HeadToHead` OHS (inject the protocol, so it can be stubbed until Stats lands)
- [ ] `LockScreenState`: the oldest live match (as `findLive`), or none: match id, sides, score, breaker, frame timer, paused (Q4 noted). Moves to the next-oldest when the shown match ends (ADR-0004).
- [ ] OHS `IsPlayerInLiveMatch(PlayerId)`: used by Players' archive guard and the "are you sure" check on start
- [ ] OHS `HavePlayedEachOther(PlayerId, PlayerId)`: used by Players' merge guard
- [ ] Projections are kept current from the match event stream

## UI (design language: 022)
- [ ] The hub's **Live** section, from `LiveMatches`:
  - Oldest first, one row per match: both colour plates and names, the score in monospaced digits, a running match timer, and a Paused label
  - Tapping a row opens the live screen. The section is hidden when there are no live matches.
- [ ] The **live screen**, from `LiveMatchScreen`:
  - Two player columns, each with a colour plate, name and huge frame count; a dot marks the breaker
  - Frame timer, match timer, and day and time are secondary
  - A head-to-head strip underneath, hidden when the players have no history
  - Controls are enabled from "available controls"
- [ ] **Paused:** a clear Paused state, timers frozen, and every control except Resume disabled
- [ ] **VoiceOver** reads the score as "Asher 4, Me 3", plus the breaker and the paused state. At accessibility Dynamic Type sizes the score stays legible.

## Non-goals
- Past-match lists and stats (Stats context)

## Acceptance criteria
- One integration test per read requirement, covering ordering, the sets score format, the paused flag and the lock-screen hand-over to the next-oldest live match
- The OHS protocols are published in the module that Players depends on

**Implementation skill:** `ddd-cqrs` · **Tests:** `ddd-testing`
