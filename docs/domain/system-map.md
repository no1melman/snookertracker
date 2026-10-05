# System Map

Nodes are actors, aggregates and external systems. Edges are commands (solid: actor → aggregate, or aggregate → external) and events/reactions (dashed). Every edge label ends with the scenario numbers that use it, so any edge traces back to its scenario doc. Everything is `(new)`: no code exists yet, so the suffix is omitted from every label.

```mermaid
flowchart LR
  %% Actors
  scorer([Scorer])
  clock([Clock])
  lifecycle([App lifecycle])
  %% Aggregates
  Match[Match]
  Player[Player]
  Template[Template]
  Series[Series]
  Preferences[Preferences]
  %% External systems
  Notifications[(iOS Notifications)]
  LockScreen[(iOS Lock Screen)]

  scorer -->|"StartMatch [S1,S2,S11]"| Match
  scorer -->|"ChooseBreaker / BreakerChosen [S4]"| Match
  scorer -->|"AwardFrame / FrameWon, SetWon, MatchTargetReached [S5,S15,S16]"| Match
  scorer -->|"RemoveFrame / FrameRemoved [S6,S15,S16]"| Match
  scorer -->|"PauseMatch / MatchPaused · ResumeMatch / MatchResumed [S7,S8]"| Match
  scorer -->|"FinishMatch / MatchFinished [S10,S15,S16,S43]"| Match
  scorer -->|"AbandonMatch / MatchAbandoned [S25,S43]"| Match
  scorer -->|"CancelMatch / MatchCancelled [S26]"| Match
  scorer -->|"CorrectMatchScore / MatchScoreCorrected [S29]"| Match
  scorer -->|"DeleteMatch / MatchDeleted [S30]"| Match
  scorer -->|"MarkMatchFinished / MatchMarkedFinished [S31]"| Match
  scorer -->|"CorrectBreaker / BreakerCorrected [S41]"| Match
  scorer -->|"OverrideMatchColour / MatchColourOverridden [S46]"| Match
  scorer -->|"read: live matches, past matches, timeline, head-to-head, stats [S9,S11,S14,S17,S18,S19]"| Match

  scorer -->|"AddPlayer / PlayerAdded [S2,S3,S48]"| Player
  scorer -->|"RenamePlayer / PlayerRenamed [S32]"| Player
  scorer -->|"ChangePlayerColour / PlayerColourChanged [S22]"| Player
  scorer -->|"MergePlayers / PlayersMerged [S33]"| Player
  scorer -->|"ArchivePlayer / PlayerArchived · UnarchivePlayer / PlayerUnarchived [S34,S35]"| Player
  scorer -->|"RemovePlayer / PlayerRemoved [S42]"| Player

  scorer -->|"DeleteTemplate / TemplateDeleted [S36]"| Template
  scorer -->|"CreateSeries / SeriesCreated [S39]"| Series
  scorer -->|"ChangeSeries / SeriesChanged · DeleteSeries / SeriesDeleted [S40]"| Series
  scorer -->|"ChangeDefaults, SetLiveMatchLimit, SetMe [S20,S21,S44,S45,S48]"| Preferences

  clock -->|"WarnLongFrame / LongFrameWarned [S37]"| Match
  clock -->|"IssueSeriesSummary / SeriesSummaryIssued [S38]"| Series
  lifecycle -->|"relaunch after a kill → AutoPauseMatch / MatchAutoPaused [S27]"| Match
  lifecycle -->|"FlagStaleMatch / StaleMatchFlagged [S28]"| Match

  Match -.->|"MatchStarted → CreateTemplate / TemplateCreated · RecordTemplateUse / TemplateUsed [S1,S2,S12]"| Template
  Match -.->|"oldest live match's events → show / update / hand over Live Activity [S47]"| LockScreen
  LockScreen -->|"AwardFrame · PauseMatch · ResumeMatch [S47]"| Match
  Match -->|"LongFrameWarned → notify [S37]"| Notifications
  Series -->|"SeriesSummaryIssued → notify [S38]"| Notifications
  Player -.->|"PlayersMerged → CombineTemplates / TemplatesCombined [S33]"| Template
  Player -.->|"PlayersMerged, PlayerRemoved → ChangeSeries / SeriesChanged [S33,S42]"| Series
  Player -.->|"PlayersMerged, PlayerRemoved then SetMe [S33,S42]"| Preferences
  Player -.->|"PlayerRemoved → DeleteMatch / MatchDeleted [S42]"| Match
  Player -.->|"PlayerRemoved → DeleteTemplate / TemplateDeleted [S42]"| Template
```

Conventions: `([ ])` actor · `[ ]` aggregate · `[( )]` external system · solid edge = command · dashed edge = event/reaction · `[S#]` = scenario numbers.

## Index

| Node | Kind | Scenarios |
|------|------|-----------|
| Scorer | Actor | 1–11, 14, 15, 16, 17–22, 25, 26, 29–36, 39–46, 48 |
| Clock | Actor | 37, 38 |
| App lifecycle | Actor | 27, 28 |
| Match | Aggregate | 1–11, 14–19, 25–31, 37, 41, 42, 43, 46, 47 |
| Player | Aggregate | 2, 3, 22, 32–35, 42, 48 |
| Template | Aggregate | 1, 2, 12, 33, 36, 42 |
| Series | Aggregate | 33, 38, 39, 40, 42 |
| Preferences | Aggregate | 2, 18, 19, 20, 21, 33, 42, 44, 45, 48 |
| iOS Notifications | External | 37, 38 |
| iOS Lock Screen | External | 47 |
