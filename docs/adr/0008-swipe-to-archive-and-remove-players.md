# ADR-0008: Swipe to archive and remove players; confirm a removal only when matches go with it

**Date:** 2026-10-06
**Status:** Accepted
**Supersedes:** —   **Superseded by:** — (refines ADR-0001's S34 and S42 triggers)

## Context
The scorer reaches for swipe-left to tidy lists: past matches, live matches, templates, players. Archiving (S34) was only reachable from Settings → Players, and removing (S42) always asked for confirmation, even when the player had no matches and nothing else would be lost.

## Decision
- **S34:** swiping an active player archives them, on the Players screen and on the New Game player list. No confirmation, because Unarchive (S35) reverses it. The existing guard still applies: a player in a live match can't be archived, and the refusal explains why.
- **S42:** swiping an archived player on the Players screen removes them.
  - If they have matches, a confirmation says how many matches will be deleted with them.
  - If they have none, they are removed straight away with no dialog. Their templates and series setups still go through the usual `PlayerRemoved` reactions.
- All swipe actions are icon-only.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| CHANGED | 34 | Archive a player | Trigger: swipe an active player (Players screen, New Game player list), as well as the context action |
| CHANGED | 42 | Remove an archived player | Trigger: swipe an archived player; confirmation only when they have matches |

- Events, aggregates, actors: none added or removed.
- Open questions: none added.

## Consequences
- `RemovePlayer` needs a count of the player's matches before it runs. That count comes from Matches' open-host query (`findByPlayer`) through the composition root, so Players does not import Matches.
- A mistaken swipe on a player with no matches loses only their templates and series setups. That was judged acceptable given the swipe is on archived players only.
