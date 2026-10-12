---
status: complete
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
updated_at: 2026-10-12T15:33:39.388610Z
completed_at: 2026-10-12T15:33:39.388610Z
transitions:
- status: in-progress
  at: 2026-10-12T15:27:09.399024Z
- status: complete
  at: 2026-10-12T15:33:39.388610Z
---
# Players edition guards

## Overview
Enforce the Free limits on Players' own data, reading `CurrentEdition` (Upgrade open host, ADR-0011). Source: `docs/ddd-requirements.md` Changes section rows for `Player`. Scenarios S2, S3, S22, S35, S48, S52.

## Requirements
- [x] `PlayerRepository.countActive()`: active players only (archived, merged away, removed excluded)
- [x] `AddPlayer`: **Free: refused when `countActive()` ≥ 5 → upgrade offer**
- [x] `UnarchivePlayer`: **Free: refused when `countActive()` ≥ 5 → upgrade offer**
- [x] `ChangePlayerColour`: Free: refused; colours kept but left out of every read while Free
- [x] `PlayerSuggestions(prefix)`, `PlayersList`: colour omitted while Free
- [x] Players over the cap after a revocation stay

### UI (design language: 022)
- [x] Add (Players screen, New Game inline add, welcome) and Unarchive route a refusal to `ShowUpgradeOffer`
- [x] No colour plates or Colour action while Free

## Non-goals
- The offer screen itself (upgrade screens spec)

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration: Free cap of 5 active (archived excluded, Me included) on add and unarchive; players over the cap after a revocation stay
- Colours refused and omitted while Free, and all shown again on unlock with no data changed

**Implementation skills:** `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - `PlayerRepository.countActive()` (SQLite: `status = 'active'`), so archived, merged-away and removed players don't count.
  - `PlayersService` reads `edition` before every guarded action:
    - `addPlayer` and `unarchivePlayer` throw `UpgradeRequired(.extraPlayers)` when `FreeLimits.allowsAnotherActivePlayer(activeCount:)` says no. The domain checks run first, so an archived name or an invalid unarchive keeps its own error.
    - `changePlayerColour` throws `UpgradeRequired(.colours)`.
    - While Free, `addPlayer` ignores the chosen colour and takes the next unused one.
  - Reads: `PlayerListItem.shownColour` is nil while Free in `players` (PlayersList) and `suggestions(prefix:)` (PlayerSuggestions). It is applied at read time over the stored rows, so unlocking shows every colour again with no write. The service subscribes to `AppUnlocked` / `AppLocked` so observers re-read.
  - UI: an attempt helper in Players routes `UpgradeRequired` to `showUpgradeOffer`. It is used by Add (the toolbar pre-checks the cap; the editor closes, then offers), Unarchive, the welcome, and New Game's inline add (a minimal catch in `NewGameView.addPlayer`). While Free, `PlayerLabel` shows the plain name instead of a colour plate (Players list, Merge, Me), the Colour action is hidden, and the editor has no picker or preview.
  - Integration tests (`PlayersEditionIntegrationTests`, real SQLite, `FixedEdition` flipped by hand) cover: `countActive` exclusions; the Free cap on add and unarchive (Me included, archived excluded, welcome included); no cap once Unlocked; players over the cap after a revocation stay, including across a relaunch; colours refused and omitted while Free and all shown again on unlock with the stored rows unchanged.
- **Decisions:**
  - The cap is only checked before a new active player is created. Nothing is archived or deleted when the edition goes back to Free.
  - `PlayerListItem.colour` keeps the stored colour, and `shownColour` is the omitted read. The composition root feeds `players` to Matches (the colour is recorded at match start) and seeds Stats from it. Blanking `colour` would record gray matches and overwrite Stats' colours, which would rewrite data. Matches and Stats hide colours on their own (ADR-0011).
  - The cap is read only from `FreeLimits`. Tests use `FreeLimits.standard.activePlayers`.
- **Remains:**
  - The offer screen itself (upgrade screens spec). Until then, `showUpgradeOffer` sets `UpgradeOfferRouter.request`.
