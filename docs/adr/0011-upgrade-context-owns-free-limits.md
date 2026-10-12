# ADR-0011: An Upgrade context owns the edition and the Free limits; each context enforces them on its own data

**Date:** 2026-10-12
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
ADR-0010 added the Edition aggregate (Free or Unlocked) and the App Store as an external system. The Free limits touch every existing context:
- Matches: one live match, most frames wins, alternate breaks, no templates, no pause by hand
- Players: 5 active players, no colours
- Stats: the newest 10 matches, no head-to-head, stats or series

Two questions follow. Where do the edition and the limit numbers live? And who counts?

## Decision
- **A new Generic context, Upgrade,** owns:
  - the `Edition` aggregate
  - the Free-limits table (live matches 1, active players 5, visible ended matches 10, allowed styles, allowed break rules, and the list of paid features)
  - unlock, restore and revoke (S49–S51)
  - the upgrade offer and benefits screens (S52, S53)
- **App Store → Upgrade: anti-corruption layer.** A StoreKit adapter translates verified transactions, Ask to Buy approvals and revocations into `Unlock` and `Lock`. No StoreKit type crosses the adapter.
- **Upgrade → Matches, Players, Stats: open host plus published language.** The three are conformist.
  - One query, "current edition and Free limits", answered from the cached edition. It works offline.
  - Two published events, `AppUnlocked` and `AppLocked`.
- **Enforcement stays in the owning context, on its own data.**
  - Players counts active players.
  - Matches counts live matches and checks the style and break rule.
  - Stats picks the newest 10 ended matches and hides the paid read models.
  - A refused action opens the upgrade offer (S52), which belongs to Upgrade.
- **Limits are entry rules, not lifecycle states.** No aggregate in Matches, Players or Stats gains a state or event because of the edition.

## Consequences
- A pricing change, such as 5 players becoming 3, is a change to one table in Upgrade.
- Upgrade depends on nothing in the core. Scoring never waits on StoreKit, because the query reads the local cache.
- The contexts must read the edition before the guarded actions. The requirements pass lists every guard.
- Alternatives rejected:
  - **Each context hard-codes its own limit.** The pricing would be spread over three contexts and drift.
  - **Upgrade asks each context for counts and decides.** The payment wrapper would depend on the core and would duplicate their read models.
  - **A shared-kernel "Licence" type in every context.** Too much coupling for one query and two events.
