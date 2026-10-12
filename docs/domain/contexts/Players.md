# Bounded Context Canvas — Players

**Classification:** Supporting
**Strategic revision:** ADR-0001 · boundaries: ADR-0002 · ADR-0011

## Purpose
Who plays: each person's unique name and colour, archiving, merging and removing them, and which player is "Me" on this device. Says nothing about how anyone is doing; that is Stats.

## Scenarios
3, 22, 32, 33, 34, 35, 42, 45, 48 (and new names entered in 1, 2)

---

## Inbound Communication

| Source | Type | Description |
|--------|------|-------------|
| Upgrade | Query / Event | Current edition and Free limits; `AppUnlocked`, `AppLocked` (conformist, ADR-0011) |
| Scorer | Command | AddPlayer, RenamePlayer, ChangePlayerColour, MergePlayers, ArchivePlayer, UnarchivePlayer, RemovePlayer, SetMe |
| Matches | Query (Matches' open host) | "Is this player in a live match?" (archive guard); "Have these two ever played each other?" (merge guard) |

## Outbound Communication

| Destination | Type | Description |
|-------------|------|-------------|
| Matches | Query | Names (suggestions, case-insensitive lookup), colours, archived flag |
| Matches, Stats | Event (published language) | `PlayerAdded`, `PlayerRenamed`, `PlayerColourChanged`, `PlayersMerged`, `PlayerArchived`, `PlayerUnarchived`, `PlayerRemoved` |
| Stats | Query | Who "Me" is |

---

## Ubiquitous Language

| Term | Type | Definition within Players | Avoid |
|------|------|---------------------------|-------|
| Player | Aggregate | A person, identified by a unique name, with a colour; active, archived, merged away or removed | "user", "member" |
| Player name | Value object | Non-blank; unique, case-insensitive; an archived player's name is blocked except via removal | — |
| Colour | Value object | A palette colour; new players get the next unused one, repeating when exhausted; not unique | — |
| Palette | Concept | The ordered set of colours new players are given | — |
| Archive | Concept | Hide a player you no longer play: out of suggestions, templates hidden, matches filtered out of stats; reversible | "delete" |
| Merge | Concept | Fold one player record into another (same person); refused if they ever played each other | — |
| Remove | Concept | Permanently delete an archived player and everything that references them | "delete" |
| Me | Concept | The player who owns this device, shown "Me (Callum)" | "user", "owner" |
| Welcome | Concept | First launch: enter your name (creates you, sets Me), then a quick walkthrough | "onboarding" |

## Commands

| Command | Intent | Handled by |
|---------|--------|-----------|
| AddPlayer | Create a player with the next palette colour | Player |
| RenamePlayer | New unique name | Player |
| ChangePlayerColour | New colour | Player |
| MergePlayers | Fold one into another | Player (guard asks Matches) |
| ArchivePlayer / UnarchivePlayer | Hide or restore | Player (archive guard asks Matches) |
| RemovePlayer | Permanently remove an archived player | Player |
| SetMe | Mark the device owner | Me setting |

## Policies

| When | Then |
|------|------|
| `PlayersMerged` | Me follows the kept player |
| `PlayerRemoved` | clear Me if it was them |

---

## Business Rules
- **Free edition (ADR-0010, ADR-0011):** at most 5 active players (Me included, archived not counted) for AddPlayer and UnarchivePlayer; colours kept but not shown. Refused actions open the upgrade offer (Upgrade).
- Names are unique case-insensitively and never blank.
- An archived player's name can't be reused unless that player is removed.
- Archiving is refused while the player is in a live match.
- A merge is refused if the two players ever played each other.
- Only archived players can be removed.
- Me is optional.

## Aggregates
- `Player` — identity, name, colour, archived/merged/removed
- `MeSetting` — the device owner's player (per device; raises no events)

## External Dependencies

| External Context | Relationship | Translation Needed? |
|-----------------|--------------|---------------------|
| Upgrade | Conformist to its open host + published language | No |
| Matches | Uses Matches' two published questions | No |

## Team

| Role | Name |
|------|------|
| Domain Expert | Business owner |
| Tech Lead | Business owner |
| Team | Solo |

## Notes
- A player's record (wins, frames, deciders) is not here: it is computed in Stats from Matches' events.
