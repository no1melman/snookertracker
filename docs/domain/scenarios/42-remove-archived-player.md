# 42 — Remove an archived player

**Type:** YOU
**Status:** new
**Source:** none
**History:** ADR-0001 (baseline), ADR-0008
**Actor:** Scorer
**Trigger / interface:** Swipe an archived player on the Players screen (icon-only action); Settings → Players (archived) → remove; or offered when typing / renaming to an archived player's name (2, 3, 32). A confirmation dialog only when they have matches.
**Description:** Permanently removes the player and all their matches. Their templates go, their setups are taken out of series, and the name becomes free.

## Relations
- Triggered by: [2], [3], [32] (offer)
- Triggers: [30] for each of their matches
- Depends on: [34]

## Inputs
- Confirmation, when the player has matches (it states how many will be deleted)

## Rules
- Only archived players
- No matches → removed without a dialog; one or more matches → confirm first
- If the player was "Me", Me is cleared

## Flow
1. Scorer removes the player, confirming if they have matches
2. Player removed; reactions clean up

## Failure paths
- Declined (when asked) → nothing changes

## Domain Events Raised
- `PlayerRemoved`

## Reactions
- when `PlayerRemoved` → delete each of their matches (`MatchDeleted`, → scenario 30); delete their templates (`TemplateDeleted`); remove their setups from series (`SeriesChanged`); clear Me

## Aggregates Touched
- `Player`, `Match`, `Template`, `Series`, `Preferences`

## External Systems
- none

## Sequence Diagram
```mermaid
sequenceDiagram
  actor S as Scorer
  participant P as Player
  participant M as Match
  participant T as Template
  participant Se as Series
  S->>P: RemovePlayer (confirmed)
  P-->>P: PlayerRemoved
  P-->>M: → DeleteMatch (each)
  P-->>T: → DeleteTemplate (each)
  P-->>Se: → ChangeSeries (remove setups)
```
