---
status: complete
created: 2026-10-05
priority: high
tags:
- matches
- domain
depends_on:
- '2'
parent: '1'
created_at: 2026-10-05T10:42:31.451003Z
updated_at: 2026-10-05T20:51:18.993901Z
completed_at: 2026-10-05T20:51:18.993901Z
transitions:
- status: in-progress
  at: 2026-10-05T19:18:17.018089Z
- status: complete
  at: 2026-10-05T20:51:18.993901Z
---

# Matches value objects

## Overview
The Matches value objects, which every Match, Template and MatchSettings behaviour builds on. Source: `docs/ddd-requirements.md` › Matches › Match › Value Objects, plus `TemplateId`/`UseCount` (Template) and `MatchDefaults`/`LiveMatchLimit` (MatchSettings). Implement each constraint exactly as the doc states it.

## Requirements
- [x] `MatchId`, `PlayerId` (the Matches reference), `TemplateId`: opaque, non-empty
- [x] `Setup`: two distinct `PlayerId`s (unordered for equality), `Game`, `MatchStyle`, `BreakRule`. Equality is template identity.
- [x] `Game` (pool | snooker), `BreakRule` (alternate default | winnerBreaks)
- [x] `MatchStyle` (mostFramesWins | raceTo(Target) | sets(sets:, frames:))
- [x] `Target`: N ≥ 1. Built from "race to N", or from "best of M" with M odd, stored as ⌈M/2⌉. It remembers how it was entered; equality is on N.
- [x] `Side` (PlayerId + display colour, may be a temporary override)
- [x] `Frame`: winner, number, set number, `Duration?` (nil when corrected in) and breaker. It must be extensible with a loss reason and a snooker points breakdown without remodelling (design-for-later).
- [x] `Score`: frames per side. For sets, also sets won and current-set frames, displayed "(1) 5 – 2 (0)".
- [x] `Duration`: elapsed minus paused, ≥ 0
- [x] `Result` (win(Side) | draw), `StartTime` (full timestamp; displays as "Fri 19:30")
- [x] `MatchStatus` with exactly the transition table in the doc
- [x] `StaleResolution`, `ChosenEndTime` (last action ≤ t ≤ now), `CappedLength` (same-pair same-weekday average, else 3 h)
- [x] `ScoreCorrection`: race to has exactly one side on the target. Sets correction produces warnings, not errors.
- [x] `UseCount` ≥ 1, `MatchDefaults` (pool, mostFramesWins, alternate), `LiveMatchLimit` 1…100 default 10

## Non-goals
- Aggregates and behaviours (later specs)

## Acceptance criteria
- Domain unit tests cover:
  - `Target`: best of odd only, ⌈M/2⌉, display as entered
  - `Setup` equality: unordered players; best of 5 equals race to 3
  - Every allowed and refused `MatchStatus` transition
  - `ChosenEndTime` bounds
  - `CappedLength` 3 h fallback
  - `ScoreCorrection` validity and warnings
  - `LiveMatchLimit` bounds

**Implementation skill:** `ddd-tactical-patterns` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):** every value object is in `ios/Sources/Matches/Domain` (`Identifiers`, `Setup`, `Target`, `Side`, `Frame`, `Tally`, `PlayDuration`, `MatchStatus`, `StaleResolution`, `ScoreCorrection`, `SettingsValues`), with smart constructors returning `Result` and decoding that re-validates.
- Every acceptance test is in `ios/Tests/Matches/DomainTests/ValueObjectTests.swift` and `MatchStatusTests.swift` (the latter checks every from/to pair against the table).
- **Decisions:**
  - `Duration` is named `PlayDuration` so it doesn't shadow `Swift.Duration`.
  - A frame's `Duration?` is `Frame.length`, plus `wonAt`, which is nil for a corrected-in frame.
  - `Result` is `MatchResult`.
  - `CappedLength` takes the same-pair same-weekday average from the caller (Stats) and falls back to 3 h.
  - The Matches `Colour` is an opaque palette reference; Players owns the palette.
- **Remains:** nothing.
