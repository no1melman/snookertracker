# ADR-0002: Templates and match settings belong to Matches; Players supplies, Matches answers two questions

**Date:** 2026-10-03
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
Strategic design grouped the model into Matches, Players and Stats. Templates were first drawn alongside players, which made Players and Matches depend on each other (Matches telling Players "a match started"). The business owner's view: a template is just a setup that isn't a live match yet; a match has everything a template has, plus what's relevant to live play. A player's record (wins, frames) is computed from matches, so it belongs in Stats, not Players.

## Decision
- `Template` and `Setup` belong to **Matches**. The baseline's `Preferences` is split by context: default game, style, break rule and the live-match limit become **Match settings** in Matches; **Me** stays in Players.
- **Players → Matches: Customer/Supplier.** Players supplies names, colours and the archived flag, and publishes `PlayersMerged` / `PlayerRemoved`, which Matches reacts to (moving or deleting matches and templates).
- **Matches → Players: open host service.** Two Players rules need match facts. Matches publishes two fixed queries: "is this player in a live match?" (archive guard) and "have these two ever played each other?" (merge guard). Players depends on nothing else in Matches.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| — | — | — | No scenario changes; boundaries only |

- Aggregates: `Preferences` partitioned into `MatchSettings` (Matches) and `MeSetting` (Players); discovery's system and event maps keep the single `Preferences` node until the next delta regenerates them
- Boundaries: as above

## Consequences
- Requirements: Template, Setup and Match settings items sit under Matches; the two queries are a Matches port that Players' archive and merge use cases call.
- Players is small and supporting; changes to it rarely touch Matches.
- Alternative rejected: templates in Players with a partnership between the two (two-way coupling for no benefit in a one-person app).
