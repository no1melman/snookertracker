---
status: planned
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
updated_at: 2026-10-12T15:13:40.468744Z
---

# Stats edition guards

## Overview
Enforce the Free limits on Stats reads and `Series`, reading `CurrentEdition` (Upgrade, ADR-0011). Projections keep building while Free so unlocking shows everything at once. Source: `docs/ddd-requirements.md` Changes section rows for Stats and `Series`. Scenarios S14, S17, S18, S19, S38, S39, S40, S52.

## Requirements
- [ ] `PastMatches`: **Free: the newest 10 ended matches plus a count of hidden ones (tapping it opens the upgrade offer); all on unlock**
- [ ] `MatchTimeline`: Free: only for the visible matches
- [ ] `HeadToHead(PlayerId, PlayerId)`: **locked while Free** (returns no figures)
- [ ] `Stats(filter)`: **locked while Free**
- [ ] Series: `CreateSeries`, `ChangeSeries`, `DeleteSeries` refused while Free; `IssueMonthlySummaries` **skipped while Free**; `SeriesList` locked while Free; the merge and removal policies (S33, S42) still run
- [ ] Projections keep building while Free; no rebuild on unlock

### UI (design language: 022)
- [ ] History shows the hidden count row, opening the offer
- [ ] Stats and Series screens open the generic offer while Free

## Non-goals
- The live-screen head-to-head greying (Matches edition guards spec); the offer screens

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration (stats): projections keep building while Free; Free shows the newest 10 and locks head-to-head and stats; unlock shows everything with no rebuild
- Integration (series): Free refuses series commands and issues no summary, while merge and removal policies still run

**Implementation skills:** `ddd-cqrs`, `ddd-application-layer` · **Tests:** `ddd-testing`
