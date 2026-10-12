---
status: planned
created: 2026-10-12
priority: high
tags:
- upgrade
- players
depends_on:
- '23'
- '11'
parent: '1'
created_at: 2026-10-12T15:13:40.456579Z
updated_at: 2026-10-12T15:13:40.456579Z
---

# Players edition guards

## Overview
Enforce the Free limits on Players' own data, reading `CurrentEdition` (Upgrade open host, ADR-0011). Source: `docs/ddd-requirements.md` Changes section rows for `Player`. Scenarios S2, S3, S22, S35, S48, S52.

## Requirements
- [ ] `PlayerRepository.countActive()`: active players only (archived, merged away, removed excluded)
- [ ] `AddPlayer`: **Free: refused when `countActive()` ≥ 5 → upgrade offer**
- [ ] `UnarchivePlayer`: **Free: refused when `countActive()` ≥ 5 → upgrade offer**
- [ ] `ChangePlayerColour`: Free: refused; colours kept but left out of every read while Free
- [ ] `PlayerSuggestions(prefix)`, `PlayersList`: colour omitted while Free
- [ ] Players over the cap after a revocation stay

### UI (design language: 022)
- [ ] Add (Players screen, New Game inline add, welcome) and Unarchive route a refusal to `ShowUpgradeOffer`
- [ ] No colour plates or Colour action while Free

## Non-goals
- The offer screen itself (upgrade screens spec)

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration: Free cap of 5 active (archived excluded, Me included) on add and unarchive; players over the cap after a revocation stay
- Colours refused and omitted while Free, and all shown again on unlock with no data changed

**Implementation skills:** `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`
