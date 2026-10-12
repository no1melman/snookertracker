---
status: complete
created: 2026-10-12
priority: high
tags:
- upgrade
- stats
- series
depends_on:
- '23'
- '13'
- '14'
- '16'
- '17'
parent: '1'
created_at: 2026-10-12T15:13:40.468744Z
updated_at: 2026-10-12T15:34:23.770835Z
completed_at: 2026-10-12T15:34:23.770835Z
transitions:
- status: in-progress
  at: 2026-10-12T15:28:15.956747Z
- status: complete
  at: 2026-10-12T15:34:23.770835Z
---
# Stats edition guards

## Overview
Enforce the Free limits on Stats reads and `Series`, reading `CurrentEdition` (Upgrade, ADR-0011). Projections keep building while Free so unlocking shows everything at once. Source: `docs/ddd-requirements.md` Changes section rows for Stats and `Series`. Scenarios S14, S17, S18, S19, S38, S39, S40, S52.

## Requirements
- [x] `PastMatches`: **Free: the newest 10 ended matches plus a count of hidden ones (tapping it opens the upgrade offer); all on unlock**
- [x] `MatchTimeline`: Free: only for the visible matches
- [x] `HeadToHead(PlayerId, PlayerId)`: **locked while Free** (returns no figures)
- [x] `Stats(filter)`: **locked while Free**
- [x] Series: `CreateSeries`, `ChangeSeries`, `DeleteSeries` refused while Free; `IssueMonthlySummaries` **skipped while Free**; `SeriesList` locked while Free; the merge and removal policies (S33, S42) still run
- [x] Projections keep building while Free; no rebuild on unlock

### UI (design language: 022)
- [x] History shows the hidden count row, opening the offer
- [x] Stats and Series screens open the generic offer while Free

## Non-goals
- The live-screen head-to-head greying (Matches edition guards spec); the offer screens

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration (stats): projections keep building while Free; Free shows the newest 10 and locks head-to-head and stats; unlock shows everything with no rebuild
- Integration (series): Free refuses series commands and issues no summary, while merge and removal policies still run

**Implementation skills:** `ddd-cqrs`, `ddd-application-layer` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - `MatchRecordsProjection` guards its reads, never its folds: `pastMatches` returns only the newest `FreeLimits.visibleEndedMatches` while Free, the new `hiddenMatchCount(filter)` counts the rest, and `timeline` is nil for a hidden match. `stats(filter)` returns `StatsReport.locked` (`isLocked`, no figures) and `headToHead` returns `HeadToHead.none`; both signatures are unchanged. `AverageFrameTime` and `AverageMatchLength` stay free (S28).
  - Series: `CreateSeries`, `ChangeSeries` and `DeleteSeries` throw `UpgradeRequired(.series)` while Free. `SeriesListProjection` takes the edition, and `series`, `setupChoices` and the new `isLocked` lock the list. `IssueMonthlySummaries` takes the edition and returns before reading anything. The merge and removal policies have no guard.
  - UI: History ends with a "N older matches hidden" row that opens the offer (`.fullHistory`). Stats and Series show a locked placeholder with an Upgrade button and open the generic offer (`.stats`, `.series`) on appear. A series command refused mid-edit opens the offer instead of an error.
  - The composition root hands the edition to `SeriesListProjection` and `IssueMonthlySummaries`.
  - Integration tests: `StatsEditionGuardsTests` (a counting store proves an unlock writes nothing and rebuilds nothing) and `SeriesEditionGuardsTests`.
- **Decisions:**
  - The visible set ignores the History filter. It is the newest ended matches in History's order (newest started first), cancelled and archived players' matches included, so the visible set doesn't move when the filter changes. The hidden count is the rows the current filter would show that the limit hides.
  - The projection and the series list subscribe to `AppUnlocked` and `AppLocked` only to bump an observed counter, so open screens re-read under the new edition. Nothing is rebuilt.
  - A month skipped while Free isn't recorded in the summary log, so the first run after an unlock still issues the previous month's summary.
  - `MonthlySummary` reads through `Stats(filter)`, so it has no figures while Free. Only the locked Series screen reaches it.
- **Remains:**
  - The live screen's greyed head-to-head (Matches edition guards spec).
