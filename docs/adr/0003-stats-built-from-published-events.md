# ADR-0003: Stats is built from Matches' and Players' published events

**Date:** 2026-10-03
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
Stats (match records, timelines, head-to-head, deciders, series, monthly summaries) is core alongside Matches. Every match is already a history of events (decisions.md). Future areas — shared matches across devices, leagues and tournaments — will want the same match events.

## Decision
- **Matches → Stats: published language, Stats conformist.** Matches publishes a fixed, documented set of match events (the `MatchStarted` event carries the setup). Stats takes them as published, with no translation, and builds its own read models. Players does the same for player events.
- **Stats → Matches: open host service.** The live screen's head-to-head and the stale-match prompt's suggested end time and capped length are queries Stats answers. Matches calls them; it never reads Stats' store.
- Deciders are computed in Stats from frames, not stored by Matches.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| — | — | — | No scenario changes; boundaries only |

- Boundaries: as above

## Consequences
- Requirements: Matches' events are a published contract — changing one is a versioned change; Stats rebuilds from them (corrections included).
- Leagues and shared matches can later consume the same events without touching Stats.
- Matches ↔ Stats is two-way, but each direction is narrow: events one way, three queries the other.
- Alternative rejected: Stats reading Matches' store directly (couples Stats to Matches' persistence and blocks sync and leagues).
