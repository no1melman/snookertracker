# 40 — Change or delete a series

**Type:** YOU
**Status:** new
**Source:** none
**History:** ADR-0001 (baseline) · ADR-0010 (changed: paid)
**Actor:** Scorer
**Trigger / interface:** Series screen → a series → rename, add/remove setups, delete
**Description:** Changes which setups a series covers, or deletes it. Matches are unaffected.

## Relations
- Depends on: [39]
- Also changed by: [33], [42] (setups repointed / removed)

## Inputs
- Name and/or setups; or delete confirmation

## Rules
- **Edition (ADR-0010):** Paid. While the edition is Free, this opens the upgrade offer (→ 52)
- Deleting a series never deletes matches

## Flow
1. Scorer edits or deletes

## Failure paths
- none

## Domain Events Raised
- `SeriesChanged`
- `SeriesDeleted`

## Reactions
- none

## Aggregates Touched
- `Series`

## External Systems
- none

## Sequence Diagram
```mermaid
sequenceDiagram
  actor S as Scorer
  participant Se as Series
  alt change
    S->>Se: ChangeSeries
    Se-->>Se: SeriesChanged
  else delete
    S->>Se: DeleteSeries
    Se-->>Se: SeriesDeleted
  end
```
