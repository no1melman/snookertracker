# ADR-0010: Free and Unlocked editions, one-off in-app purchase

**Date:** 2026-10-12
**Status:** Accepted
**Supersedes:** —   **Superseded by:** —

## Context
The app is about to be published on the App Store. The business owner wants it free to download for tracking a live match, with everything else behind a single, one-off in-app purchase (about £2.99). The free tier should feel useful but come with friction, so that the purchase is the obvious fix.

## Decision
- **Two editions per device: Free and Unlocked.** Unlocked comes from one non-consumable in-app purchase that never expires. There is no subscription. Family Sharing is on.
- **The Free edition allows:**
  - one live match at a time
  - most frames wins only, with alternate breaks only
  - up to 5 active players, "Me" included (archived players don't count)
  - the newest 10 ended matches shown
  - no player colours
  - no aggregate figures: head-to-head, stats and series
  - no templates, no lock screen, no manual pause or resume
- **What the Free edition keeps:** auto-pause after a kill (S27), resume from that auto-pause, and the stale check (S28). These are automatic, not manual, so a force-quit acts as a free pause. That loophole is accepted.
- **Nothing is ever deleted or rewritten to enforce a limit.** Matches beyond the newest 10 are hidden, not deleted. Templates are still recorded silently (S12). Colours are kept but not shown. Unlocking reveals everything at once.
- **Paid features show an upgrade offer when touched (S52).**
  - The templates area and the pause button each show an "Upgrade now" prompt in place.
  - Every other paid menu item opens a generic "Upgrade once, forever, to unlock" screen.
  - A menu item listing what upgrading unlocks (S53) is shown until the app is unlocked.
  - The offer never appears on launch and is never repeated as a pop-up.
- **Revocation (refund, or Family Sharing ending) returns the device to Free** (S51). It deletes nothing. Live matches keep their style and run to the end, but nothing paid can be started.
- **The edition is cached on the device.** Being offline never re-locks the app.

## Model delta

| Change | # | Scenario | Detail |
|--------|---|----------|--------|
| ADDED | 49 | Unlock full version | One-off purchase through the App Store; includes Ask to Buy approval arriving later |
| ADDED | 50 | Restore purchase | Restore link on the upgrade screen |
| ADDED | 51 | Purchase revoked | App Store refund or Family Sharing ending → Free |
| ADDED | 52 | Show the upgrade offer | Prompts in place on templates and pause; generic screen elsewhere |
| ADDED | 53 | See what upgrading unlocks | Menu item; hidden once unlocked |
| CHANGED | 1, 12, 36 | Templates | Paid; S12 still records templates silently while Free |
| CHANGED | 2 | Start by entering details | Free: most frames wins and alternate breaks only |
| CHANGED | 3, 33, 34, 35 | Player management | Free: at most 5 active players; adding or unarchiving past the cap opens the upgrade offer |
| CHANGED | 7, 8 | Pause / resume | Paid; resuming after an auto-pause (S27) stays free |
| CHANGED | 11, 43, 44 | Several live matches | Free: limit fixed at 1; the setting is paid |
| CHANGED | 14, 18, 19, 38, 39, 40 | Head-to-head, stats, series | Paid |
| CHANGED | 15, 16, 21 | Race to, sets, style and break defaults | Paid |
| CHANGED | 22, 46 | Colours | Paid; colours are kept but not shown while Free |
| CHANGED | 47 | Lock screen | Paid |
| CHANGED | 17, 29, 30 | Past matches, correct, delete | Free: newest 10 ended matches only; older ones hidden |

- Aggregates added: **Edition** (per device: Free or Unlocked).
- External systems added: **App Store** (StoreKit).
- Events added: `AppUnlocked`, `AppLocked`.
- Open questions: none added.

## Consequences
- Every limited scenario reads the Edition before acting. The limits are rules at the point of entry, not changes to the Match, Player, Template or Series lifecycles.
- Because nothing is deleted, unlocking and revoking can't lose data. Stats, the head-to-head and series figures appear complete straight away after unlocking.
- Strategic design should decide where Edition sits: in its own context, or as a policy shared by the others.
- Alternatives rejected:
  - Deleting matches beyond 10, which would lose the data people pay to see.
  - Counting archived players towards the cap. Juggling players is friction that sells the upgrade.
  - Blocking the force-quit pause, which would make the kill case worse for everyone.
  - A subscription.
