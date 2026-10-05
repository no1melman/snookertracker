---
status: planned
created: 2026-10-05
priority: high
tags:
- stats
- cqrs
depends_on:
- '13'
- '12'
parent: '1'
created_at: 2026-10-05T10:42:31.499454Z
updated_at: 2026-10-05T10:42:31.499454Z
---

# Stats: deciders, filtered stats & open-host queries

## Overview
Stats computations: the decider rules, filtered stats, head-to-head, and the averages Matches needs for stale matches. Source: `docs/ddd-requirements.md` › Stats › Stats read models. Scenarios S10, S14, S18, S19, S28.

## Requirements
- [ ] `Deciders` as pure functions:
  - Decider: a frame won from level at the end of a set or a frames-style match, in any set
  - Match decider: such a frame that is the match's last frame (also a decider)
  - Set decider: a deciding set played with sets level (its own tally, never a match decider)
- [ ] `Stats(filter)`:
  - Groups: opponent, weekday (combinable)
  - Filters: opponent, weekday, game, style, date range, include abandoned, include archived players (the series filter is added by the series spec, 016)
  - Fields: W–D–L, frames won–lost, deciders, match deciders, set deciders, win %, average frame time
  - Point of view: Me (`WhoAmI`) or a chosen player
- [ ] OHS `HeadToHead(PlayerId, PlayerId)`:
  - W–D–L, frames, and deciders (only when non-zero)
  - All finished matches, any game or style; excludes the live match
- [ ] OHS `AverageFrameTime(PlayerId)`
- [ ] OHS `AverageMatchLength(players, weekday)`: finished matches only; nil when there are none
- [ ] Inclusion rules: finished only by default, abandoned opt-in, cancelled never, archived opt-in

## UI (design language: 022)
- [ ] The **Stats** screen, from `Stats(filter)`:
  - Point of view: Me, or a chosen player
  - Filters: opponent, weekday, game, style, date range, include abandoned, include archived
  - Grouping by opponent and/or weekday
  - Figures in monospaced digits: W–D–L, frames, deciders, match and set deciders, win %, and average frame time
  - One rivalry in focus, with the rest listed below it as context
- [ ] The live screen's head-to-head strip (009) reads `HeadToHead`

## Non-goals
- Outlier-excluding stats (out of scope, per decisions.md)

## Acceptance criteria
- Domain unit tests on the worked examples:
  - 3–1 / 9–8 → match decider
  - 3–2 / 9–5 → set decider only
  - 3–2 / 9–8 → both
  - An earlier set at 9–8 → decider only
- Unit tests: W–D–L with draws; each inclusion rule
- Integration tests: head-to-head excludes the live match; nil average length when there are no matches

**Implementation skills:** `ddd-cqrs`, `ddd-tactical-patterns` · **Tests:** `ddd-testing`
