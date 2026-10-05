# 27 — Auto-pause when the app is killed

**Type:** AUTO
**Status:** new
**Source:** none
**History:** ADR-0001 (baseline) · ADR-0004 (changed: detected on relaunch) · ADR-0005 (changed: pause at the later of the background time and the last action)
**Actor:** App lifecycle
**Trigger / interface:** App launch, when the last session ended without a clean return to the foreground (swiped away, killed by iOS, the phone died, or a crash)
**Description:** iOS gives no warning when it kills a suspended app, so the pause can't happen at the moment of death. On the next launch, each match that was running is paused as of when the app stopped being used. Switching apps or locking the phone does **not** pause.

## Relations
- Related: [8] resumes; [9] leaving the app never pauses
- Related: [28] runs straight after on the same launch, measuring idle time from this pause

## Inputs
- The time the app last went to the background, recorded on every backgrounding and cleared on every return to the foreground

## Rules
- Only a kill pauses; backgrounding and locking never do
- Pause time: the later of the recorded background time and that match's last action (lock-screen actions can come after backgrounding). With no background time recorded (the app was on screen when it died), the last action
- Already-paused matches are untouched
- Runs before the stale check (S28)

## Flow
1. App launches and detects that the last session was killed
2. Each running live match is paused, stamped with the pause time above (never earlier than its last action)
3. The stale check (S28) runs

## Failure paths
- none: the pause time is always known (at least the last action)

## Domain Events Raised
- `MatchAutoPaused` (stamped with the pause time, which may be earlier than when it is raised)

## Reactions
- when `MatchAutoPaused` → stop long-frame warnings (→ scenario 37); update the lock screen if it is the shown match (→ scenario 47)

## Aggregates Touched
- `Match`

## External Systems
- iOS app lifecycle

## Sequence Diagram
```mermaid
sequenceDiagram
  participant OS as App lifecycle
  participant M as Match
  OS->>OS: launch; last session killed
  OS->>M: AutoPauseMatch (at max(background time, last action))
  M-->>M: MatchAutoPaused
  OS->>M: FlagStaleMatch (S28)
```
