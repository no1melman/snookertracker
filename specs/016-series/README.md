---
status: in-progress
created: 2026-10-05
priority: medium
tags:
- stats
depends_on:
- '13'
- '11'
parent: '1'
created_at: 2026-10-05T10:42:31.507618Z
updated_at: 2026-10-06T19:45:19.555405Z
transitions:
- status: in-progress
  at: 2026-10-06T19:45:19.555405Z
---

# Series

## Overview
`Series`: a named group of setups. Every past and future match with one of its setups belongs to it. Source: `docs/ddd-requirements.md` › Stats › Series. Scenarios S33, S39, S40, S42.

**Also depends on** 014 (adds the series filter to `Stats(filter)`). Not in frontmatter: `leanspec rel` is not migrated yet.

## Requirements
- [x] Value objects: `SeriesId`, `SeriesName` (non-blank), `Setup` (as published in `MatchStarted`, conformist), `Month`
- [x] `Series.create(name, setups)` raises `SeriesCreated`
- [x] `change(name?, add:, remove:)` raises `SeriesChanged`
- [x] `delete()` raises `SeriesDeleted`; it never touches matches
- [x] A setup can be in several series
- [x] `SeriesRepository`: `getById`, `save`, `findAll`, `findContainingPlayer`
- [x] Use cases: `CreateSeries`, `ChangeSeries`, `DeleteSeries`
- [x] Policies: `RepointSeriesOnMerge` (`PlayersMerged`) and `RemovePlayerFromSeries` (`PlayerRemoved`)
- [x] `SeriesList` read model: id, name, setups
- [ ] The series filter in `Stats(filter)` resolves membership by setup. The helper is ready: `SeriesMembership.filter(for:)` gives a `SeriesFilter`, and its `contains(record, resolve:)` says whether a match belongs. Plugging it into `Stats(filter)` is 014's job.

## UI (design language: 022)
- [x] The **Series** screen, from `SeriesList`:
  - Create and edit in a sheet (name, choose setups)
  - Delete by swiping a series row (icon-only action), with a confirmation stating that the matches are kept
- [ ] The series filter appears in Stats (014)

## Non-goals
- The monthly summary (separate spec)

## Acceptance criteria
- Domain unit tests: create, change, delete
- Integration tests: membership by setup (past and future matches), several series per setup, the merge and removal policies

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Code:** `ios/Sources/Stats/{Domain,Application,Infrastructure,Presentation}/Series/`. Tests are in `ios/Tests/Stats/{DomainTests,IntegrationTests}/Series/` (15 domain, 7 integration).
- **Persistence:** its own tables, `series` and `series_setups` (migration `stats.series.001`), through `SQLiteSeriesRepository`. The same adapter is also the `SeriesListReader`.
- **Screen:** `SeriesView` reads `@Environment(\.seriesPorts)`. Swipe → Delete is icon-only (ADR-0008), and the confirmation says the matches are kept.
- **Left:** the series filter in Stats (014), the monthly summary (separate spec), and composition-root wiring.

## Decisions
- `Setup` is Stats' own copy of the `MatchStarted` setup shape (conformist). Its equality matches Matches': players unordered, targets compared by race-to value. `Setup.key` is the text identity used in storage.
- Membership is never stored per match. It is worked out at read time from the record's setup, following merges (`SeriesFilter.followingMerges`), because Stats' records keep the original player ids.
- "One or more setups" is checked on create, and in `ChangeSeries` when the sheet saves. Policies may still empty a series (its last player removed). The series is kept so the scorer can edit or delete it.
- A change that changes nothing raises no `SeriesChanged`, so the policies are idempotent.
- Series events are Stage 1 only, so nothing is dispatched.
- The sheet offers setups from the `SeriesSetupCatalog` port. `StatsStoreSetupCatalog` adapts it over the Stats store: recorded matches and players, with removed players left out.
