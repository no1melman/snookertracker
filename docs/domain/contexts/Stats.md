# Bounded Context Canvas — Stats

**Classification:** Core
**Strategic revision:** ADR-0001 · boundaries: ADR-0003 · ADR-0011

## Purpose
Turns the history of matches into insight: past matches and their timelines, head-to-head, stats by opponent and day of the week, deciders, and series with monthly summaries. Read-side, built from Matches' and Players' published events; the only thing written here is a series.

## Scenarios
14, 17, 18, 19, 38, 39, 40 (and the series cascades of 33, 42)

---

## Inbound Communication

| Source | Type | Description |
|--------|------|-------------|
| Upgrade | Query / Event | Current edition and Free limits; `AppUnlocked`, `AppLocked` (conformist, ADR-0011) |
| Matches | Event (published language) | All match events, taken as published; builds match records, deciders and figures |
| Players | Event (published language) | Player events: names, archived, merged, removed |
| Players | Query | Who "Me" is |
| Scorer | Command / Query | CreateSeries, ChangeSeries, DeleteSeries; view past matches, timelines, stats with filters |
| Clock (iOS) | Command | IssueSeriesSummary on the 1st of the month |

## Outbound Communication

| Destination | Type | Description |
|-------------|------|-------------|
| Matches | Query | Head-to-head figures for the live screen; a player's average frame time; same-weekday average match length |
| iOS Notifications | Command (via adapter) | Monthly series summary |

---

## Ubiquitous Language

| Term | Type | Definition within Stats | Avoid |
|------|------|-------------------------|-------|
| Match record | Read model | An ended match as Stats sees it: result, timeline, deciders; rebuilt after corrections | "match" (the live thing is in Matches) |
| Timeline | Read model | A match record's frames in order: winner, frame time, match time, running score, corrections marked | — |
| Opponent | Concept | The other player in a match record, from Me's (or a chosen player's) point of view | "player" |
| Me | Concept | From Players; the default point of view | — |
| Head-to-head | Read model | All-time finished matches between two players: Matches W–D–L, Frames, Deciders (when non-zero) | "aggregate score" |
| Decider | Concept | A frame won from level at the end of a set or frames-style match (8–8 → 9–8), in any set | — |
| Match decider | Concept | A decider that is the match's last frame; also counts as a decider | — |
| Set decider | Concept | A deciding set played with sets level; its own tally, never a match decider | — |
| Stats filter | Value object | Opponent, day of week, game, style, series, date range, include abandoned, include archived, show cancelled (past matches) | — |
| Series | Aggregate | A named group of setups ("Fridays with Asher"); every match with one of its setups belongs to it; small groups between friends | "bucket", "league" |
| Monthly summary | Read model | A series' figures for last month, with the change since the month before | — |
| Average frame time | Figure | Mean frame length for a player; used in stats and by Matches' stale-match suggestion | — |

## Commands

| Command | Intent | Handled by |
|---------|--------|-----------|
| CreateSeries / ChangeSeries / DeleteSeries | Maintain series | Series |
| IssueSeriesSummary | Monthly summary per series with matches | Series |

## Policies

| When | Then |
|------|------|
| any match event (Matches) | update match records, head-to-head, figures |
| `PlayersMerged` (Players) | ChangeSeries: repoint setups to the kept player |
| `PlayerRemoved` (Players) | ChangeSeries: remove that player's setups |
| `SeriesSummaryIssued` | notify |

---

## Business Rules
- **Free edition (ADR-0010, ADR-0011):** only the newest 10 ended matches shown (older hidden, never deleted); head-to-head, stats by opponent and day, and series locked; no monthly summary issued. Refused actions open the upgrade offer (Upgrade).
- Only finished matches count by default; abandoned only when included; cancelled never counts.
- Matches with archived players are hidden unless included.
- Head-to-head on the live screen counts every finished match between the two, any game, any style.
- A setup can be in several series; deleting a series never touches matches.
- A summary uses "you" only when Me is in the series; otherwise it lists each pairing.

## Aggregates
- `Series` — name and setups; issues monthly summaries
- Read models: match records and timelines, head-to-head, stats figures

## External Dependencies

| External Context | Relationship | Translation Needed? |
|-----------------|--------------|---------------------|
| Upgrade | Conformist to its open host + published language | No |
| Matches | Conformist to Matches' published match events | No: takes them as published |
| Players | Conformist to Players' published player events | No |
| iOS Notifications | Anti-corruption layer | Yes: adapter at the edge |

## Team

| Role | Name |
|------|------|
| Domain Expert | Business owner |
| Tech Lead | Business owner |
| Team | Solo |

## Notes
- Later: advanced stats that exclude outliers; leagues and tournaments as their own context (possibly a separate app) consuming the same published match events.
- Deferred question: Q5 in `docs/domain/decisions.md`.
