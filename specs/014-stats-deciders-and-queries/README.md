---
status: in-progress
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
updated_at: 2026-10-06T19:45:19.278089Z
transitions:
- status: in-progress
  at: 2026-10-06T19:45:19.278089Z
---

# Stats: deciders, filtered stats & open-host queries

## Overview
Stats computations: the decider rules, filtered stats, head-to-head, and the averages Matches needs for stale matches. Source: `docs/ddd-requirements.md` › Stats › Stats read models. Scenarios S10, S14, S18, S19, S28.

## Requirements
- [x] `Deciders` as pure functions:
  - Decider: a frame won from level at the end of a set or a frames-style match, in any set
  - Match decider: such a frame that is the match's last frame (also a decider)
  - Set decider: a deciding set played with sets level (its own tally, never a match decider)
- [x] `Stats(filter)`:
  - Groups: opponent, weekday (combinable)
  - Filters: opponent, weekday, game, style, date range, include abandoned, include archived players (the series filter is added by the series spec, 016)
  - Fields: W–D–L, frames won–lost, deciders, match deciders, set deciders, win %, average frame time
  - Point of view: Me (`WhoAmI`) or a chosen player
- [x] OHS `HeadToHead(PlayerId, PlayerId)`:
  - W–D–L, frames, and deciders (only when non-zero)
  - All finished matches, any game or style; excludes the live match
- [x] OHS `AverageFrameTime(PlayerId)`
- [x] OHS `AverageMatchLength(players, weekday)`: finished matches only; nil when there are none
- [x] Inclusion rules: finished only by default, abandoned opt-in, cancelled never, archived opt-in

## UI (design language: 022)
- [x] The **Stats** screen, from `Stats(filter)`:
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

## Implementation notes (2026-10-06)
- Code: `Deciders` in `ios/Sources/Stats/Domain/Deciders.swift`; `Stats(filter)` read models in `Application/StatsReadModels.swift`, answered by `MatchRecordsProjection` (`Application/StatsQueries.swift`); OHS protocol `MatchStatsQueries` + `HeadToHead` in `Stats/Published/MatchStatsQueries.swift`; `StatsView` in Presentation.
- Tests: `Tests/Stats/DomainTests/DecidersTests.swift` (13, worked examples and edge cases); `Tests/Stats/ContractTests/StatsQueriesTests.swift` (22, real Matches aggregate, store and wire feeding Stats).
- **Decider decisions:** "level" needs at least one frame each, so a race to 1 or a one-frame match has no deciders. Most frames wins: only the last frame of the match can be a decider (and is then the match decider). A match decider is a decider frame that ends the match (wins the last set), so an abandoned match has none. A set decider counts only once the deciding set is won. Deciders come from the frames as played; a corrected score changes W–D–L and frames, not deciders.
- **Figures:** frames won–lost use the score as it stands (after correction). Abandoned matches (when included) add frames, deciders and frame times, are counted as `abandoned`, and have no result; win % = won ÷ (won + drawn + lost). Average frame time is overall and per player (frames the point of view won / lost).
- **Point of view:** the query takes a player id; Me (`WhoAmI`) comes from Players through the `me` closure on `StatsPorts`. With no Me, the screen asks whose stats to show.
- **Weekday:** from the match's start time in the projection's `Calendar` (injectable; tests use UTC). `AverageMatchLength` takes a `Calendar` weekday Int (1 = Sunday), so Matches needs no Stats types beyond the protocol.
- **Merges and removals:** player ids are followed through merges in every query (OHS included); removed players' matches never count. HeadToHead ignores the archived filter.
- **Series seam:** `StatsFilter.series: SeriesFilter?` (from 016) filters by setup, merges followed. The Stats screen doesn't offer a series picker yet.
- Left for integration: the live screen's head-to-head strip (009, Matches presentation) reading `MatchStatsQueries.headToHead`; the stale prompt (020/S28) reading `averageFrameTime` / `averageMatchLength`; hub navigation to `StatsView`; the series picker in the Stats filter sheet.
