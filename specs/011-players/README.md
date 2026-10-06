---
status: in-progress
created: 2026-10-05
priority: high
tags:
- players
depends_on:
- '2'
- '9'
parent: '1'
created_at: 2026-10-05T10:42:31.487824Z
updated_at: 2026-10-05T19:18:17.465535Z
transitions:
- status: in-progress
  at: 2026-10-05T19:18:17.465535Z
---

# Players

## Overview
The Players context's `Player` aggregate end to end: domain, repository, use cases and read models. Source: `docs/ddd-requirements.md` › Players › Player. Scenarios S2, S3, S22, S32–S35, S42, S48.

**Also depends on** 005 (`Match.delete`, for the removal cascade) and 008 (the template policies). Not in frontmatter: `leanspec rel` is not migrated yet.

## Requirements
- [x] Value objects:
  - `PlayerId`
  - `PlayerName`: non-blank, case-insensitive
  - `Colour`: not unique
  - `Palette`: next unused, repeating from the start when exhausted
  - `PlayerStatus`: Active → Archived | MergedAway; Archived → Active | Removed
- [x] `Player.add(name, colour)`: name unique among active and archived players. Raises `PlayerAdded`.
- [x] `rename(name)`: unique, and not an archived player's name. Raises `PlayerRenamed`.
- [x] `changeColour(colour)` raises `PlayerColourChanged`
- [x] `mergeInto(kept)`: both active, and they never played each other (Matches OHS). → MergedAway. Raises `PlayersMerged`.
- [x] `archive()`: Active, and not in a live match (Matches OHS). Raises `PlayerArchived`.
- [x] `unarchive()`: Archived only. Raises `PlayerUnarchived`.
- [x] `remove()`: Archived only. Raises `PlayerRemoved`.
- [x] `PlayerRepository`: `getById`, `save`, `findByName` (case-insensitive, incl. archived), `nextUnusedColour`
- [x] Use cases:
  - `AddPlayer`: an archived name returns an error offering `RemovePlayer`
  - `RenamePlayer`, `ChangePlayerColour`
  - `MergePlayers`, `ArchivePlayer`, `UnarchivePlayer`
  - `RemovePlayer`: confirmation only when the player has matches. The count comes from Matches' `findByPlayer` through the composition root (ADR-0008).
- [x] Read models:
  - `PlayerSuggestions(prefix)`: id, name, colour; active players only, case-insensitive prefix
  - `PlayersList`: id, name, colour, status; active and archived sections
- [x] All seven events are published as Stage 2 (consumed by Matches, Stats and the Me policies)
- [ ] Matches-side policies:
  - `MovePlayerMatches` on `PlayersMerged`: repoints the `PlayerId`, recorded as a correction event
  - `DeleteMatch` on `PlayerRemoved`, for each of their matches
  - `DeleteTemplate` on `PlayerRemoved`, for each of their templates
  - `CombineTemplatesAfterMerge` on `PlayersMerged`
  - `TemplateList` hides templates with an archived player (`PlayerArchived` / `PlayerUnarchived`)

## UI (design language: 022)
- [x] The **Players** screen, from `PlayersList`:
  - Active and Archived sections. Each row shows a colour plate and name; archived rows are greyed.
  - Add from the toolbar
  - Context actions: Rename, Colour (from the fixed palette, still an open decision in 022), Merge into…, Archive or Unarchive, and Remove (archived only)
  - Swipe (icon-only, ADR-0008): an active row → Archive, with no confirmation. An archived row → Remove, which asks first only when the player has matches and says how many will be deleted; with none, the player is removed at once.
- [ ] The **New Game** player list: swipe an active player → Archive (ADR-0008)
- [x] **Refusals** explain themselves:
  - Adding an archived name offers Remove
  - A merge is refused when the two have played each other
  - Archive is refused while the player is in a live match
- [x] The New Game player picker uses `PlayerSuggestions`, with inline add

## Non-goals
- The Me setting (separate spec)

## Acceptance criteria
- Domain unit tests:
  - Name uniqueness, case-insensitive
  - The archived-name block
  - Palette next and repeat
  - Every `PlayerStatus` transition, allowed and refused
- Integration tests:
  - Merge refused when they played each other
  - Archive refused while in a live match
  - Merge combines templates that become identical
  - Templates with an archived player are hidden, and reappear on unarchive
  - Removal cascades to matches and templates. The series and Me cascades are verified in their own specs (016, 012).

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs`, `ddd-domain-events` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):**
  - The `Player` aggregate and its value objects are in `ios/Sources/Players/Domain`, with domain tests in `ios/Tests/Players/DomainTests` that cover every acceptance item.
  - `SQLitePlayerRepository` is state-stored, with a `name_key` column for case-insensitive lookup.
  - `PlayerEventWire` maps all seven events to the published `PlayerEventPublished`.
- **Done (2026-10-06):**
  - `PlayersService` covers every use case: Add, Rename, ChangePlayerColour, Merge, Archive, Unarchive, Remove and SetMe. It serves `PlayersList`, `PlayerSuggestions` (`suggestions(prefix:)`) and `matchCount(of:)`.
  - Archive and merge ask Matches' `PlayerMatchQueries` (in `MatchesPublished`). The count for the remove confirmation comes from the same protocol.
  - AddPlayer and RenamePlayer refuse an archived name with `nameHeldByArchivedPlayer(name, archived:)`. The editor turns that into an offer to remove that player and then retries the save.
  - UI: `PlayersView` has icon-only swipes (Archive on active rows, Remove on archived rows), the full context menu, a `MergePicker` sheet with a confirmation, and a Remove confirmation that states the match count, shown only when the count is above 0.
  - Integration tests (`PlayerLifecycleIntegrationTests`) run over real in-memory SQLite with a fake `PlayerMatchQueries`. They cover:
    - archive refused while live, unarchive, and remove (archived only)
    - merge refused when the two played each other, or when either player isn't active
    - merge frees the name, and Me follows the kept player
    - removal clears Me
    - the archived-name offer
    - the suggestion prefix
- **Decisions:**
  - Outside facts reach the aggregate as arguments: `sameNamed` from the repository, and the `isInLiveMatch` and `havePlayedEachOther` booleans for the Matches OHS.
  - `Palette` repeats by fewest users, earliest first.
  - A merged-away or removed player's name is free again.
  - `PlayersService.matchQueries` can be set after construction, because Matches is built after Players in the composition root. Until it is set, archive and merge are refused (`notAllowedNow`) and `matchCount` is 0.
  - The Me policies run in-context on the domain events, right after the save and before the dispatch.
  - Swipe-to-remove has no full swipe, so a removal always takes a deliberate tap.
- **Remains:**
  - The New Game swipe-to-archive (Matches presentation).
  - All of the Matches-side policies (they need 005 delete and 008), and their template and cascade integration tests.
  - Composition-root wiring: setting `players.matchQueries` to Matches' implementation, and moving New Game suggestions onto `suggestions(prefix:)`.
