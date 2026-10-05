# ADR-0006: A match is event-sourced

**Date:** 2026-10-05
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
The business owner decided during discovery that a match's in-game actions are events on its stream and that changes after it ends are alterations, never overwrites (`decisions.md` › Notes for later passes). It was implemented in specs 004–006 but never recorded as an ADR (Q6). "Records are sacred" (PRODUCT.md) depends on it: a correction must leave the original visible, and Stats must be able to rebuild every record.

## Decision
- **The `Match` aggregate is event-sourced.** Its state is derived only by applying its own events in order (`Match.rehydrate`). Each behaviour validates against current state and records new events; nothing else is stored as the source of truth.
- **One append-only stream per match** in the device's SQLite database. Each event has an id, the origin device, a stream version, a stable type name and a schema version. Appends check the expected stream version (optimistic concurrency), so a stale writer is refused rather than silently merged.
- **Post-end changes are new events** (`MatchScoreCorrected`, `MatchMarkedFinished`, `MatchDeleted`). Events already stored are never rewritten or removed, including on delete.
- **Stage 2 events are the published language** (ADR-0003). Their wire form (type name + schema version + JSON payload) is a versioned contract shared by the store and `MatchEventPublished`. Changing a payload means a new schema version, with old versions still readable.
- **Other aggregates are not event-sourced.** Template, MatchSettings, Player and MeSetting store current state; their events are published but not the source of truth.
- **No snapshots** until rehydration is measurably slow (a match is tens of events).

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| — | 1–31 | Match scenarios | Persistence decision only; no scenario, event or aggregate changes |

- Open questions: Q6 resolved.

## Consequences
- Full history and a full-state export (spec 021) come for free: every stream can be read in order.
- Corrections keep the original score next to the altered one, in Stats and History.
- Stats can catch up or rebuild from Matches' published history (spec 013) without reading Matches' tables.
- Multi-device scoring later is possible: event ids and origin device avoid a single-writer assumption, and version conflicts are detected.
- Cost: read models must be projected (live list, lock screen, Stats) instead of queried from a table, and event schemas need versioning discipline.
- Alternatives rejected: state-stored match plus an audit log (two sources of truth that can drift); overwriting on correction (breaks "records are sacred").
