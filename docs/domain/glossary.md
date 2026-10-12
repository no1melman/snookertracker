# Domain Glossary

## Actors
- **Scorer** — the person holding the phone and recording the match; usually also a player. The only human actor for now.
- **Clock** — time-based triggers: long-frame warnings, the monthly series summary.
- **App lifecycle** — iOS opening the app: auto-pause after a kill, stale-match check.

## Aggregates
- **Match** — one contest between two players under a setup, from start to finished, abandoned or cancelled; holds its frames, breaker, pauses and later corrections as a history.
- **Player** — a person identified by a unique, case-insensitive name, with a colour; active, archived, merged away or removed.
- **Template** — a setup played before, used to start a new match quickly; listed most used first.
- **Series** — a named group of setups (e.g. "Fridays with Asher"); every match with one of its setups belongs to it. A stats filter with a monthly summary. Small groups between friends; not a league.
- **Preferences** — per-device settings: default game, style and break rule, the live-match limit, and who "Me" is.
- **Edition** — per device: Free or Unlocked. Unlocked by a one-off in-app purchase; cached on the device; read by every limited scenario (ADR-0010).

## Commands
StartMatch · ChooseBreaker · CorrectBreaker · AwardFrame · RemoveFrame · PauseMatch · ResumeMatch · AutoPauseMatch · FlagStaleMatch · FinishMatch · AbandonMatch · CancelMatch · FinishAllMatches · CorrectMatchScore · MarkMatchFinished · DeleteMatch · OverrideMatchColour · WarnLongFrame · AddPlayer · RenamePlayer · ChangePlayerColour · MergePlayers · ArchivePlayer · UnarchivePlayer · RemovePlayer · CreateTemplate · RecordTemplateUse · CombineTemplates · DeleteTemplate · CreateSeries · ChangeSeries · DeleteSeries · IssueSeriesSummary · ChangeDefaults · SetLiveMatchLimit · SetMe · Unlock · Lock

## Domain Events
MatchStarted · BreakerChosen · BreakerCorrected · FrameWon · SetWon · MatchTargetReached · FrameRemoved · MatchPaused · MatchAutoPaused · MatchResumed · LongFrameWarned · StaleMatchFlagged · MatchColourOverridden · MatchFinished · MatchAbandoned · MatchCancelled · MatchScoreCorrected · MatchMarkedFinished · MatchDeleted · PlayerAdded · PlayerRenamed · PlayerColourChanged · PlayersMerged · PlayerArchived · PlayerUnarchived · PlayerRemoved · TemplateCreated · TemplateUsed · TemplatesCombined · TemplateDeleted · SeriesCreated · SeriesChanged · SeriesDeleted · SeriesSummaryIssued · AppUnlocked · AppLocked

## Policies (when → then)
See [event-map.md](./event-map.md#policies-when-x--then-y).

## Value Objects
- **Setup** — what a match is before play: two players (unordered), game, match style with targets, break rule. Identity of a template.
- **Game** — Pool | Snooker.
- **Match style** — Most frames wins (open-ended; draws possible) | Race to N frames | Sets (race to S sets, each race to F frames).
- **Target** — race to N (N ≥ 1); entered as "race to N" or "best of M" (M odd), stored as race to ⌈M/2⌉, shown as entered.
- **Break rule** — Alternate breaks (default) | Winner breaks.
- **Player name** — non-blank, unique case-insensitively.
- **Colour** — from a palette; new players get the next unused one, repeating when exhausted. Not unique.
- **Frame** — winner, number, set number, length, breaker; a frame added by correction has no length.
- **Frame length / match length** — elapsed time minus paused time. Approximate and a third-class figure.
- **Score** — frames per player; for sets, sets won plus current-set frames, shown "(1) 5 – 2 (0)".
- **Result** — win or draw.
- **Decider** — a frame won from level at the end of a set or frames-style match (8–8 → 9–8), in any set.
- **Match decider** — a decider that is the match's last frame (also counted as a decider).
- **Set decider** — a deciding set played with sets level (2–2 in race to 3); its own tally, never a match decider.
- **Start time** — full date stored; day and time shown ("Fri 19:30").
- **Me** — the device owner's player, shown "Me (Callum)".
- **Free limits** — one live match; most frames wins with alternate breaks; 5 active players (Me included, archived not counted); newest 10 ended matches shown; no colours, templates, pause by hand, head-to-head, stats, series or lock screen.
- **Upgrade offer** — "Upgrade now" in place (templates, pause) or the generic "Upgrade once, forever, to unlock" screen, with Buy and Restore.

## Rules / Invariants
- A match has two different players; nobody plays themselves.
- Nothing else is allowed until the first breaker is chosen.
- The next breaker is derived from the frames and the break rule, never stored per frame; sets don't affect it; a breaker correction resets the starting point.
- While paused, everything is disabled except resume and the match menu.
- Only shutdown pauses a match; backgrounding and locking never do.
- − never changes the timers.
- Frame 1 and the match timer start at match start.
- Finishing a race-to or sets match before its target means abandoning it, unless marked finished anyway.
- Finish, Abandon and Cancel are in the match menu and need confirmation.
- Ended matches: Abandoned → Finished is allowed; Finished → Abandoned is not; Cancelled never changes.
- Corrections after a match ends are recorded as corrections; the original stays in the history.
- A race-to correction must put exactly one player on the target.
- Live matches ≤ the live-match limit (default 10, max 100; fixed at 1 while Free).
- A stale match is one with no action for 6 hours; only it can have its length capped.
- Names are unique case-insensitively; archived names are blocked except via removal.
- A merge is refused if the two players ever played each other.
- Archiving is refused while the player is in a live match.
- Every new setup becomes a template at match start (silently while Free).
- "Best of" only accepts odd numbers.
- Free limits are never enforced by deleting or rewriting anything: older matches are hidden, colours unshown, templates unlisted.
- Auto-pause after a kill and resuming from it are free; pausing by hand is paid.
- The upgrade offer is never shown on launch or repeated as a pop-up.
- Offline never re-locks the app; a revocation never ends or changes a live match.

## External Systems
- **iOS Notifications** — long-frame warnings, monthly summaries.
- **iOS Lock Screen (Live Activities)** — the oldest live match, with + and pause/resume; the next-oldest takes over when it ends.
- **iOS app lifecycle** — launch signals, including detecting that the last session was killed.
- **App Store (StoreKit)** — the one-off unlock purchase, restore, Ask to Buy approvals and revocations.
