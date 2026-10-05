---
status: in-progress
created: 2026-10-05
priority: critical
tags:
- matches
- infrastructure
- event-sourcing
depends_on:
- '4'
parent: '1'
created_at: 2026-10-05T10:42:31.466873Z
updated_at: 2026-10-05T20:21:31.981470Z
transitions:
- status: in-progress
  at: 2026-10-05T20:21:31.981470Z
---

# Match event store & repository

## Overview
Event-sourced persistence for `Match` and the `MatchRepository` port. Source: `docs/ddd-requirements.md` › Matches › Match › Repository Port and Persistence note, plus Design-for-later constraints.

## Requirements
- [ ] An append-only event store on the device's local database, one stream per match, with optimistic concurrency on the stream version
- [ ] `MatchRepository`: `getById` (rehydrate) and `save` (append new events, then dispatch)
- [ ] `findLive()`: live matches, oldest started first
- [ ] `findByPlayer(PlayerId)`: every match with that player
- [ ] Event serialisation is versioned (Stage 2 events are a published contract)
- [ ] Design for later: a stream can accept events from more than one device (event ids and origin device, no single-writer assumption)
- [ ] Every stream can be read in full, in order (used by the export spec)

## Non-goals
- Snapshots (add only if rehydration is measurably slow)
- Multi-device sync itself

## Acceptance criteria
- Integration tests cover:
  - save → getById round-trip
  - A concurrency conflict detected
  - `findLive` ordering
  - `findByPlayer`
  - Reading a full stream in order

**Implementation skills:** `ddd-event-sourcing`, `ddd-repositories` · **Tests:** `ddd-testing`
