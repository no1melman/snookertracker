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
- [ ] Use cases:
  - `AddPlayer`: an archived name returns an error offering `RemovePlayer`
  - `RenamePlayer`, `ChangePlayerColour`
  - `MergePlayers`, `ArchivePlayer`, `UnarchivePlayer`
  - `RemovePlayer`: confirmation only when the player has matches. The count comes from Matches' `findByPlayer` through the composition root (ADR-0008).
- [ ] Read models:
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
- [ ] The **Players** screen, from `PlayersList`:
  - Active and Archived sections. Each row shows a colour plate and name; archived rows are greyed.
  - Add from the toolbar
  - Context actions: Rename, Colour (from the fixed palette, still an open decision in 022), Merge into…, Archive or Unarchive, and Remove (archived only)
  - Swipe (icon-only, ADR-0008): an active row → Archive, with no confirmation. An archived row → Remove, which asks first only when the player has matches and says how many will be deleted; with none, the player is removed at once.
- [ ] The **New Game** player list: swipe an active player → Archive (ADR-0008)
- [ ] **Refusals** explain themselves:
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
  - `PlayersService` covers AddPlayer, RenamePlayer and ChangePlayerColour, and serves `PlayersList`.
  - `PlayerEventWire` maps all seven events to the published `PlayerEventPublished`.
  - UI: `PlayersView` (Active and Archived sections, greyed rows, add, Rename and Colour) and New Game's inline add.
- **Decisions:**
  - Outside facts reach the aggregate as arguments: `sameNamed` from the repository, and the `isInLiveMatch` and `havePlayedEachOther` booleans for the Matches OHS.
  - `Palette` repeats by fewest users, earliest first.
  - A merged-away or removed player's name is free again.
  - Suggestions are active players (adapter in `AppComposition`), not yet filtered by prefix.
- **Remains:**
  - The Merge, Archive, Unarchive and Remove use cases and their context actions and refusal UI. Today AddPlayer's archived-name error only explains itself; it doesn't offer Remove.
  - A `PlayerSuggestions(prefix)` query.
  - All of the Matches-side policies (they need 005 delete and 008).
  - The integration tests for merge, archive, templates and the cascade.
