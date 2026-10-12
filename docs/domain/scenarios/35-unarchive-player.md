# 35 — Unarchive a player

**Type:** YOU
**Status:** new
**Source:** none
**History:** ADR-0001 (baseline) · ADR-0010 (changed: blocked at the Free player cap)
**Actor:** Scorer
**Trigger / interface:** Settings → Players (archived) → unarchive
**Description:** Everything archiving hid comes back as it was.

## Relations
- Depends on: [34]

## Inputs
- Player

## Rules
- **Edition (ADR-0010):** Free: refused while 5 players are active; opens the upgrade offer (→ 52)
- Player is archived

## Flow
1. Scorer unarchives the player

## Failure paths
- none

## Domain Events Raised
- `PlayerUnarchived`

## Reactions
- none

## Aggregates Touched
- `Player`

## External Systems
- none

## Sequence Diagram
```mermaid
sequenceDiagram
  actor S as Scorer
  participant P as Player
  S->>P: UnarchivePlayer
  P-->>P: PlayerUnarchived
```
