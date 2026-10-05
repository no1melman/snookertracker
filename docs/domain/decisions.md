# Domain Decision Log

## Out-of-scope scenarios
Considered during discovery and explicitly excluded for now.

| Scenario considered | Reason excluded | ADR |
|---------------------|-----------------|-----|
| 23 — Record why a frame was lost (e.g. potting the black out of turn) | Later. **Design for it:** a frame must be able to carry a loss reason without remodelling | ADR-0001 |
| 24 — Upload everything saved on the phone to the web | Later. **Design for it:** all saved state (every match's full history) must be uploadable in full | ADR-0001 |
| Watching a live match from another device | Later | ADR-0001 |
| Two people scoring the same match from their own phones | Later; needs an Android app | ADR-0001 |
| Advanced stats that leave out outliers (e.g. missed short frames, long match times) | Later | ADR-0001 |
| Backing up the on-device database to files | Later, if the storage supports it | ADR-0001 |
| A game server | Later | ADR-0001 |
| Sharing a result to WhatsApp | Later | ADR-0001 |
| Shot clocks | Later | ADR-0001 |
| Leagues (submit a match to a league) | Later, as a separate linked app; series stay small | ADR-0001 |
| Configurable long-frame thresholds | Fixed at 30 min, then every 10 min | ADR-0001 |

## Retired scenarios
Existed in the model or in code; not carried forward. Number retained, never reused.

| # | Scenario | Reason | Source (if it exists in code) | ADR |
|---|----------|--------|-------------------------------|-----|

## Merged scenarios

| # | Scenario | Merged into | Reason | ADR |
|---|----------|-------------|--------|-----|
| 13 | Skip the template screen when there are no templates | 2 | A screen rule about reaching scenario 2; changes nothing | ADR-0001 |

## Notes for later passes
- **Event stream per match (implementation decision from the business owner):** in-game actions are events on the match's stream; changes after a terminal event are recorded as alterations, never overwrites. For `ddd-requirements` / `ddd-event-sourcing`.
- **Storage:** local database on the device for now; see 24 above.
- **Language:** Swift; the `ddd-*` implementation skills will be extended to cover it.

## Open questions
Each needs an owner. A deferred question blocks implementation of its scenario. An answer re-enters through a discovery delta.
Status: `open` · `answered` (waiting for `/ddd delta`) · `deferred` · `resolved (ADR-NNNN)`

Q1–Q5 are deferred by the business owner to **revisit during implementation**; they do not block the MVP.

| # | Scenario | Question | Raised by | Owner | Status |
|---|----------|----------|-----------|-------|--------|
| Q1 | S29 | What happens if the phone dies part-way through a correction? | discovery | Business owner | deferred |
| Q2 | S29 | Two corrections in a row: does the second build on the first, and how does the timeline show them? | discovery | Business owner | deferred |
| Q3 | S5, S15, S16 | What does + do while a Finish/Continue prompt is showing? | discovery | Business owner | deferred |
| Q4 | S6, S47 | A lock-screen + arrives at the same moment as an in-app −: which wins? | discovery | Business owner | deferred |
| Q5 | S38 | A match ends while the monthly summary is being made: is it in this month's summary or the next? | discovery | Business owner | deferred |
| Q6 | S1–S31 (Match) | Record the decision that a match is event-sourced (actions are events on its stream; post-end changes are alterations) as an ADR | requirements | Business owner | resolved (ADR-0006) |
| Q7 | S27, S47 | Lock-screen buttons work while the app is in the background, so a frame can be scored after the background time. Pausing at the background time would put the pause before that frame. Pause at the later of the background time and the last action? | requirements | Business owner | resolved (ADR-0005) |
