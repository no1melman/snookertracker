# ADR-0009: A merge moves the folded-in player's matches with `MatchPlayerMoved`

**Date:** 2026-10-06
**Status:** Accepted
**Supersedes:** —   **Superseded by:** — (completes ADR-0001's S33 reactions)

## Context
S33 says every match of the folded-in player moves to the kept one. A match is event-sourced (ADR-0006): its players are fixed by `MatchStarted`, and stored events are never rewritten. So nothing in Matches could repoint a player, and `MovePlayerMatches` was blocked. Templates already had the same move as `TemplatePlayerMoved` (spec 011). Stats follows merges at read time through `mergedInto`, but only for the ids a record started with.

## Decision
- **New Stage 2 event `MatchPlayerMoved`** (`from`, `to`, `at`), wire type `MatchPlayerMoved`, schema 1. It is raised by `Match.movePlayer(from:to:at:)`.
- **It is a correction, not play.** It is allowed in every status except Deleted, live matches included. It does not reset the idle time. The side keeps this match's colour.
- **It is refused** when `from` isn't in the match, or when `to` is already in it. Moving onto the other side would make a player play themselves, and the merge guard (`havePlayedEachOther`) already refuses that merge.
- **Applying it** repoints every reference to `from`: setup, side, frame winners and breakers, breaker origin and result. Events before it still name `from`, and events after it name `to`.
- **`MovePlayerMatches` on `PlayersMerged`** loads each of the folded-in player's matches (`findByPlayer`), applies `movePlayer`, and saves, publishes and projects through `MatchUseCases.commit`. It works match by match and skips one that fails. A deleted match is left as it is.
- **Stats applies the event.** Merge resolution alone isn't enough: frames and results recorded after the move name `to`, while the record would still say `from`, and they would land on the wrong side. Repointing `from` to `to` can't double-apply, because the kept player resolves to themselves.
- `TemplatePlayerMoved` (spec 011) is the Template equivalent. It isn't published.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| CHANGED | 33 | Merge two players | Reaction: `MovePlayer` on each of the folded-in player's matches (`MatchPlayerMoved`); templates move with `TemplatePlayerMoved` before combining |

- Events: `MatchPlayerMoved` (Match, Stage 2) and `TemplatePlayerMoved` (Template, internal) added.
- Aggregates, actors: none added or removed.
- Open questions: none added.

## Consequences
- The match stream index (`match_streams.first_player` / `second_player`) is refreshed on every append. This lets `findByPlayer`, `matchCount` and `havePlayedEachOther` follow a move straight away.
- A moved match's history still shows the folded-in id before the move. Readers follow `MatchPlayerMoved`, or Stats' merge resolution, to show the kept player.
- Alternatives rejected:
  - Rewriting `MatchStarted`, which would break "records are sacred" (ADR-0006).
  - Resolving merges only at read time in Matches. That would need a player alias table inside Matches, and the `findByPlayer` guards would be wrong until it was consulted.
