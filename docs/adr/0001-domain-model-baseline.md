# ADR-0001: Domain model baseline for Snooker Tracker

**Date:** 2026-10-02
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
A new iOS app (Swift) for tracking pool and snooker matches between friends, scored live on one phone. No code exists. Discovery ran in full mode from the business owner's notes, through probe rounds (actors, lifecycles, time, going wrong, outside systems), two walkthrough passes and a gap analysis.

## Decision
The model is 45 live scenarios across five aggregates — Match, Player, Template, Series, Preferences — with Scorer, Clock and App lifecycle as actors and iOS Notifications and the iOS Lock Screen as external systems. A match is a history of events; corrections after it ends are recorded as alterations. Data stays on the device for now and must be uploadable in full later.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| ADDED | 1–12, 14–22, 25–48 | all live scenarios | Status new; see `docs/domain/README.md` |
| MERGED | 13 | Skip the template screen | into 2 |
| OUT OF SCOPE | 23, 24 | Frame-loss reasons; web upload | later, with "design for it" constraints |

- Vocabulary: see `docs/domain/glossary.md`
- Events: 34 events; see `docs/domain/event-map.md`
- Lifecycle: Match (AwaitingBreaker, InPlay, Paused, AwaitingConfirmation, Finished, Abandoned, Cancelled, Deleted); Player (Active, Archived, MergedAway, Removed); Template (Active, Deleted); Series (Active, Deleted); Preferences (Configured)
- Boundaries: not yet drawn; next `/ddd strategic`

## Consequences
- Requirements: the first `docs/ddd-requirements.md` will be all `build` items
- Code: greenfield; nothing is `existing` or `changing`
- Open questions raised: Q1–Q5 (owner: business owner), deferred to implementation; non-blocking for the MVP
- Out of scope: see `docs/domain/decisions.md` (live viewing, two-phone scoring, advanced stats, file backup, game server, WhatsApp sharing, shot clocks, leagues)
