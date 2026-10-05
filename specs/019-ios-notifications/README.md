---
status: planned
created: 2026-10-05
priority: medium
tags:
- ios
- infrastructure
depends_on:
- '15'
- '17'
parent: '1'
created_at: 2026-10-05T10:42:31.520822Z
updated_at: 2026-10-05T10:42:31.520822Z
---

# iOS notifications adapter

## Overview
A UserNotifications anti-corruption adapter for the long-frame warnings (S37) and the monthly series summaries (S38). Source: `docs/ddd-requirements.md` › Cross-cutting › Context boundaries, and `WarnLongFrame`.

## Requirements
- [ ] A UserNotifications adapter in infrastructure for the `NotificationScheduler` port defined in 015
- [ ] Long frame: schedule local notifications at 30 min, then every 10 min. Reschedule on `FrameWon` or `MatchResumed`; cancel on a pause or the end of the match. Thresholds are fixed (not configurable).
- [ ] Monthly summary: deliver `SeriesSummaryIssued` as a notification on the 1st
- [ ] Ask for notification permission at a sensible point (not on first launch before the welcome)

## Non-goals
- Configurable thresholds (out of scope, per decisions.md)

## Acceptance criteria
- Adapter tests: the schedule is computed correctly; it is rescheduled and cancelled on the right events
- Checked manually on the simulator

**Implementation skill:** `ddd-application-layer` (ports) · **Tests:** `ddd-testing`
