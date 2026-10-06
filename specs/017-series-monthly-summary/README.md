---
status: complete
created: 2026-10-05
priority: low
tags:
- stats
depends_on:
- '16'
- '14'
parent: '1'
created_at: 2026-10-05T10:42:31.511653Z
updated_at: 2026-10-06T20:12:09.430798Z
completed_at: 2026-10-06T20:12:09.430798Z
transitions:
- status: complete
  at: 2026-10-06T20:12:09.430798Z
---

# Series monthly summary

## Overview
A monthly summary on the 1st, for each series with matches in the previous month. Source: `docs/ddd-requirements.md` › Stats › Series. Scenario S38.

## Requirements
- [x] `issueSummary(month)`: needs at least one match of its setups in that month. Raises `SeriesSummaryIssued` (Stage 2 → iOS Notifications).
- [x] `IssueMonthlySummaries`: Clock, on the 1st, for the previous month; `findAll` → `issueSummary` where eligible
- [x] `MonthlySummary(series, month)` read model:
  - Per pairing, or "you" when Me is in the series
  - Matches W–D–L, frames and deciders
  - Change since the previous month
- [x] Resolve or re-defer **Q5**: a match that ends while the summary is being made. Re-deferred (see Decisions).

## UI (design language: 022)
- [x] The **monthly summary** screen, from `MonthlySummary`:
  - Opens from the notification (019) and from the series
  - Per pairing, or "you" when Me is in the series
  - W–D–L, frames, deciders, and the change since the previous month

## Non-goals
- The notification delivery mechanics (iOS notifications spec)

## Acceptance criteria
- Unit test: the summary guard
- Integration tests: a summary only for series with matches; "you" vs per-pairing; month-over-month change

**Implementation skills:** `ddd-tactical-patterns`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Code:** `ios/Sources/Stats/{Domain,Application,Infrastructure,Presentation}/Series/Summary/`. The published event is in `ios/Sources/Stats/Published/SeriesSummaryIssuedPublished.swift`. Tests are in `ios/Tests/Stats/{DomainTests,IntegrationTests}/Series/Summary/` (4 domain, 6 integration).
- **Persistence:** `SQLiteSeriesSummaryLog` keeps one row per series and month issued, in the `series_summaries_issued` table (migration `stats.series.summary.001`).
- **Screen:** `MonthlySummaryView(series:month:)` reads `SeriesPorts.summaries`. A chart button on each Series row opens it on last month, and arrows step through the months. For the notification, `MonthlySummaryView(series:year:month:)` takes the published event's fields.
- **Left:** composition-root wiring (below) and the notification adapter (019).
  - `MonthlySummaryProjection(stats: matchRecords, series: seriesRepository, me: { players' WhoAmI })`
  - `IssueMonthlySummaries(repository:summaries:log: SQLiteSeriesSummaryLog(db:), dispatcher:)`, with `run()` called after `catchUp` on launch and on every return to the foreground
  - `SeriesPorts(..., summaries:)`

## Decisions
- `issueSummary` is an extension on `Series` that returns the event and changes nothing on the aggregate. Its guards: the series is not deleted, the month is over, and there are one or more matches. The application layer counts the matches from `MonthlySummary`, and `SeriesSummaryLog` makes sure each month is issued only once.
- **Eligibility** follows the summary's own count: finished matches only, archived players included, merges followed. A month with only abandoned or cancelled matches gets no summary.
- **The clock is read on launch and on foreground**, not on the 1st exactly, and there are no background tasks. The first run in a month issues the previous month. A month with no matches is not recorded, so a match from that month taken in late (catch-up) can still earn its summary.
- **"You"** applies when Me is a player in one of the series' setups. The "you" line counts all of Me's series matches that month. Pairings without Me follow it, each seen from its setup's first player. Lines with no matches that month are left out.
- **Change since the previous month** is this month's figures minus last month's (W–D–L, frames, deciders, win-rate points). When last month had no matches, the screen says there is nothing to compare with.
- **Q5, re-deferred.** It is still the business owner's call, and an answer needs a `/ddd delta` ADR. The build makes the question mostly moot:
  - A match belongs to the month it **started** in, the same rule as the Stats date filter.
  - The summary is worked out each time it is read, never stored. A match that started last month and ended after the summary was issued shows when the summary is opened. It is missing only from the notification headline.
  - A match still live at issue time does not count towards eligibility.
  - Proposed answer for the delta: "last month's, by start time; the summary is live".
