---
status: planned
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
updated_at: 2026-10-05T10:42:31.495503Z
---

# Stats match records & history

## Overview
Stats projections of match history, built only from Matches' and Players' published (Stage 2) events. Stats is conformist. Source: `docs/ddd-requirements.md` › Stats › Stats read models (ADR-0003). Scenarios S10, S17, S25, S26, S29–S31.

**Also depends on** 005 (`MatchScoreCorrected`, `MatchMarkedFinished` and `MatchDeleted` come from the ending spec). Not in frontmatter: `leanspec rel` is not migrated yet.

## Requirements
- [ ] `MatchRecord` projection, built from all Stage 2 match events:
  - Result, status, sides, setup, start and end, length, frames, corrections
  - Rebuilt on `MatchScoreCorrected` and `MatchMarkedFinished`
  - Removed on `MatchDeleted`
- [ ] Player projection from the player events: names, colours, archived, merges and removals
- [ ] `PastMatches`:
  - Fields: day + time, players, score, style, finished or abandoned
  - Newest first
  - Filters: show cancelled, include archived players
- [ ] `MatchTimeline`: per frame, the winner, frame time, match time at that point and running score; corrections are marked
- [ ] Projections can be rebuilt from scratch by replaying the events

## UI (design language: 022)
- [ ] The **History** screen, from `PastMatches`:
  - Newest first, grouped by month
  - Each row: day and time, colour plates and names, score, style, and an Abandoned label
  - Filter toggles: show cancelled, include archived players
- [ ] The **match detail**, from `MatchTimeline`:
  - Per frame: the winner, frame time, match time and running score
  - Corrections are marked next to the original value, never in place of it
  - The actions are in 015

## Non-goals
- Aggregated stats and deciders (separate spec)

## Acceptance criteria
- Integration tests: projections are correct after corrections, mark-finished, deletions, merges and removals; past-match ordering and filters

**Implementation skills:** `ddd-cqrs`, `ddd-domain-events` · **Tests:** `ddd-testing`
