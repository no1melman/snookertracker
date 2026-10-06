---
status: complete
created: 2026-10-05
priority: high
tags:
- stats
- cqrs
depends_on:
- '6'
- '11'
parent: '1'
created_at: 2026-10-05T10:42:31.495503Z
updated_at: 2026-10-06T20:12:53.666751Z
completed_at: 2026-10-06T20:12:53.666751Z
transitions:
- status: in-progress
  at: 2026-10-05T20:46:00.685596Z
- status: complete
  at: 2026-10-06T20:12:53.666751Z
---

# Stats match records & history

## Overview
Stats projections of match history, built only from Matches' and Players' published (Stage 2) events. Stats is conformist. Source: `docs/ddd-requirements.md` › Stats › Stats read models (ADR-0003). Scenarios S10, S17, S25, S26, S29–S31.

**Also depends on** 005 (`MatchScoreCorrected`, `MatchMarkedFinished` and `MatchDeleted` come from the ending spec). Not in frontmatter: `leanspec rel` is not migrated yet.

## Requirements
- [x] `MatchRecord` projection, built from all Stage 2 match events:
  - Result, status, sides, setup, start and end, length, frames, corrections
  - Rebuilt on `MatchScoreCorrected` and `MatchMarkedFinished`
  - Removed on `MatchDeleted`
- [x] Player projection from the player events: names, colours, archived, merges and removals
- [x] `PastMatches`:
  - Fields: day + time, players, score, style, finished or abandoned
  - Newest first
  - Filters: show cancelled, include archived players
- [x] `MatchTimeline`: per frame, the winner, frame time, match time at that point and running score; corrections are marked
- [x] Projections can be rebuilt from scratch by replaying the events

## UI (design language: 022)
- [x] The **History** screen, from `PastMatches`:
  - Newest first, grouped by month
  - Each row: day and time, colour plates and names, score, style, and an Abandoned label
  - Filter toggles: show cancelled, include archived players
- [x] The **match detail**, from `MatchTimeline`:
  - Per frame: the winner, frame time, match time and running score
  - Corrections are marked next to the original value, never in place of it
  - The actions are in 015

## Non-goals
- Aggregated stats and deciders (separate spec)

## Acceptance criteria
- Integration tests: projections are correct after corrections, mark-finished, deletions, merges and removals; past-match ordering and filters

## Implementation notes (2026-10-05)
- Code: `ios/Sources/Stats/{Application,Infrastructure,Presentation}`; tests: `ios/Tests/Stats/ContractTests` (19, real Matches store + wire + Stats SQLite).
- **Conformist reader:** Stats decodes the published JSON payloads with its own tolerant DTOs (`PublishedLanguage.swift`); no Matches/Players internals imported.
- **Stats keeps its own event log** (`stats_match_events`, keyed by event id) and folds each match from it on every event, so corrections, mark-finished and frame removals rebuild the record; `MatchDeleted` drops it. `rebuildAll()` re-folds everything.
- **Backfill:** Matches publishes an open-host `MatchEventHistory` (in `MatchesPublished`, implemented by `SQLiteMatchEventHistory`). At launch the composition root subscribes Stats before any command can dispatch, then `catchUp` fetches each stream past Stats' per-stream checkpoint. Idempotent with live dispatch.
- **Players** are state-stored (no history to replay), so the composition root seeds Stats' player table from the current players list at launch; later changes arrive as events. Merges resolve at query time to the kept player; removed players' matches are hidden (Matches deletes them per S42).
- Altered = score corrected. Mark-finished is shown under Alterations in detail.
- Gaps: delete/correct/mark-finished actions wait for the 015 commands; read-model gaps from 022 (breaker per frame) are in `MatchTimeline` but not shown.

**Implementation skills:** `ddd-cqrs`, `ddd-domain-events` · **Tests:** `ddd-testing`

## Progress (2026-10-06)
- Verified: every requirement and UI item was already ticked, and the code and tests are in place (`MatchRecordsTests` and the Stats integration tests, which pass in `swift test`). Nothing to change.
