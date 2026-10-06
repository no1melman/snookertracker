---
status: planned
created: 2026-10-05
priority: medium
tags:
- stats
depends_on:
- '13'
- '11'
parent: '1'
created_at: 2026-10-05T10:42:31.507618Z
updated_at: 2026-10-05T10:42:31.507618Z
---

# Series

## Overview
`Series`: a named group of setups. Every past and future match with one of its setups belongs to it. Source: `docs/ddd-requirements.md` › Stats › Series. Scenarios S33, S39, S40, S42.

**Also depends on** 014 (adds the series filter to `Stats(filter)`). Not in frontmatter: `leanspec rel` is not migrated yet.

## Requirements
- [ ] Value objects: `SeriesId`, `SeriesName` (non-blank), `Setup` (as published in `MatchStarted`, conformist), `Month`
- [ ] `Series.create(name, setups)` raises `SeriesCreated`
- [ ] `change(name?, add:, remove:)` raises `SeriesChanged`
- [ ] `delete()` raises `SeriesDeleted`; it never touches matches
- [ ] A setup can be in several series
- [ ] `SeriesRepository`: `getById`, `save`, `findAll`, `findContainingPlayer`
- [ ] Use cases: `CreateSeries`, `ChangeSeries`, `DeleteSeries`
- [ ] Policies: `RepointSeriesOnMerge` (`PlayersMerged`) and `RemovePlayerFromSeries` (`PlayerRemoved`)
- [ ] `SeriesList` read model: id, name, setups
- [ ] The series filter in `Stats(filter)` resolves membership by setup

## UI (design language: 022)
- [ ] The **Series** screen, from `SeriesList`:
  - Create and edit in a sheet (name, choose setups)
  - Delete by swiping a series row (icon-only action), with a confirmation stating that the matches are kept
- [ ] The series filter appears in Stats (014)

## Non-goals
- The monthly summary (separate spec)

## Acceptance criteria
- Domain unit tests: create, change, delete
- Integration tests: membership by setup (past and future matches), several series per setup, the merge and removal policies

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`
