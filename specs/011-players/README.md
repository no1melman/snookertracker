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
- [ ] Value objects:
  - `PlayerId`
  - `PlayerName`: non-blank, case-insensitive
  - `Colour`: not unique
  - `Palette`: next unused, repeating from the start when exhausted
  - `PlayerStatus`: Active → Archived | MergedAway; Archived → Active | Removed
- [ ] `Player.add(name, colour)`: name unique among active and archived players. Raises `PlayerAdded`.
- [ ] `rename(name)`: unique, and not an archived player's name. Raises `PlayerRenamed`.
- [ ] `changeColour(colour)` raises `PlayerColourChanged`
- [ ] `mergeInto(kept)`: both active, and they never played each other (Matches OHS). → MergedAway. Raises `PlayersMerged`.
- [ ] `archive()`: Active, and not in a live match (Matches OHS). Raises `PlayerArchived`.
- [ ] `unarchive()`: Archived only. Raises `PlayerUnarchived`.
- [ ] `remove()`: Archived only. Raises `PlayerRemoved`.
- [ ] `PlayerRepository`: `getById`, `save`, `findByName` (case-insensitive, incl. archived), `nextUnusedColour`
- [ ] Use cases:
  - `AddPlayer`: an archived name returns an error offering `RemovePlayer`
  - `RenamePlayer`, `ChangePlayerColour`
  - `MergePlayers`, `ArchivePlayer`, `UnarchivePlayer`
  - `RemovePlayer`, with confirmation
- [ ] Read models:
  - `PlayerSuggestions(prefix)`: id, name, colour; active players only, case-insensitive prefix
  - `PlayersList`: id, name, colour, status; active and archived sections
- [ ] All seven events are published as Stage 2 (consumed by Matches, Stats and the Me policies)
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
  - Context actions: Rename, Colour (from the fixed palette, still an open decision in 022), Merge into…, Archive or Unarchive, and Remove (archived only, with confirmation)
- [ ] **Refusals** explain themselves:
  - Adding an archived name offers Remove
  - A merge is refused when the two have played each other
  - Archive is refused while the player is in a live match
- [ ] The New Game player picker uses `PlayerSuggestions`, with inline add

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
