---
status: planned
created: 2026-10-05
priority: low
tags:
- stats
depends_on:
- '16'
- '14'
parent: '1'
created_at: 2026-10-05T10:42:31.511653Z
updated_at: 2026-10-05T10:42:31.511653Z
---

# Series monthly summary

## Overview
A monthly summary on the 1st, for each series with matches in the previous month. Source: `docs/ddd-requirements.md` › Stats › Series. Scenario S38.

## Requirements
- [ ] `issueSummary(month)`: needs at least one match of its setups in that month. Raises `SeriesSummaryIssued` (Stage 2 → iOS Notifications).
- [ ] `IssueMonthlySummaries`: Clock, on the 1st, for the previous month; `findAll` → `issueSummary` where eligible
- [ ] `MonthlySummary(series, month)` read model:
  - Per pairing, or "you" when Me is in the series
  - Matches W–D–L, frames and deciders
  - Change since the previous month
- [ ] Resolve or re-defer **Q5**: a match that ends while the summary is being made

## UI (design language: 022)
- [ ] The **monthly summary** screen, from `MonthlySummary`:
  - Opens from the notification (019) and from the series
  - Per pairing, or "you" when Me is in the series
  - W–D–L, frames, deciders, and the change since the previous month

## Non-goals
- The notification delivery mechanics (iOS notifications spec)

## Acceptance criteria
- Unit test: the summary guard
- Integration tests: a summary only for series with matches; "you" vs per-pairing; month-over-month change

**Implementation skills:** `ddd-tactical-patterns`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`
