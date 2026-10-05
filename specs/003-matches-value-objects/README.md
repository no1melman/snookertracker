---
status: in-progress
created: 2026-10-05
priority: high
tags:
- matches
- domain
depends_on:
- '2'
parent: '1'
created_at: 2026-10-05T10:42:31.451003Z
updated_at: 2026-10-05T19:18:17.018089Z
transitions:
- status: in-progress
  at: 2026-10-05T19:18:17.018089Z
---

# Matches value objects

## Overview
The Matches value objects, which every Match, Template and MatchSettings behaviour builds on. Source: `docs/ddd-requirements.md` › Matches › Match › Value Objects, plus `TemplateId`/`UseCount` (Template) and `MatchDefaults`/`LiveMatchLimit` (MatchSettings). Implement each constraint exactly as the doc states it.

## Requirements
- [ ] `MatchId`, `PlayerId` (the Matches reference), `TemplateId`: opaque, non-empty
- [ ] `Setup`: two distinct `PlayerId`s (unordered for equality), `Game`, `MatchStyle`, `BreakRule`. Equality is template identity.
- [ ] `Game` (pool | snooker), `BreakRule` (alternate default | winnerBreaks)
- [ ] `MatchStyle` (mostFramesWins | raceTo(Target) | sets(sets:, frames:))
- [ ] `Target`: N ≥ 1. Built from "race to N", or from "best of M" with M odd, stored as ⌈M/2⌉. It remembers how it was entered; equality is on N.
- [ ] `Side` (PlayerId + display colour, may be a temporary override)
- [ ] `Frame`: winner, number, set number, `Duration?` (nil when corrected in) and breaker. It must be extensible with a loss reason and a snooker points breakdown without remodelling (design-for-later).
- [ ] `Score`: frames per side. For sets, also sets won and current-set frames, displayed "(1) 5 – 2 (0)".
- [ ] `Duration`: elapsed minus paused, ≥ 0
- [ ] `Result` (win(Side) | draw), `StartTime` (full timestamp; displays as "Fri 19:30")
- [ ] `MatchStatus` with exactly the transition table in the doc
- [ ] `StaleResolution`, `ChosenEndTime` (last action ≤ t ≤ now), `CappedLength` (same-pair same-weekday average, else 3 h)
- [ ] `ScoreCorrection`: race to has exactly one side on the target. Sets correction produces warnings, not errors.
- [ ] `UseCount` ≥ 1, `MatchDefaults` (pool, mostFramesWins, alternate), `LiveMatchLimit` 1…100 default 10

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
