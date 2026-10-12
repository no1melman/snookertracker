# Bounded Context Canvas — Upgrade

**Classification:** Generic
**Strategic revision:** ADR-0010 · boundaries: ADR-0011

## Purpose
Decides what this device may use: Free or Unlocked. Owns the one-off in-app purchase, restore and revocation, the Free-limits table, and the screens that sell the upgrade. Never counts anything itself; the other contexts enforce the limits on their own data.

## Scenarios
49, 50, 51, 52, 53 (and the edition rule read by 1–3, 7, 8, 11, 12, 14–19, 21, 22, 29, 30, 33–36, 38–40, 43, 44, 46, 47)

---

## Inbound Communication

| Source | Type | Description |
|--------|------|-------------|
| Scorer | Command | Purchase (49), RestorePurchases (50); open the benefits screen (53) |
| App Store (via ACL) | Event | Purchase verified (now, or later through Ask to Buy) → `Unlock`; revoked (refund, Family Sharing ended) → `Lock` |
| Matches, Players, Stats | Query | "Current edition and Free limits" |
| Matches, Players, Stats | Command | ShowUpgradeOffer(feature) when a paid feature is touched while Free (52) |

## Outbound Communication

| Destination | Type | Description |
|-------------|------|-------------|
| Matches, Players, Stats | Event (published language) | `AppUnlocked`, `AppLocked` |
| Matches, Players, Stats | Query (open host) | Edition and Free limits: live matches 1, active players 5, visible ended matches 10, styles allowed (most frames wins), break rules allowed (alternate), paid features |
| App Store (via ACL) | Command | Purchase, restore, listen for transaction updates |

---

## Ubiquitous Language

| Term | Type | Definition within Upgrade | Avoid |
|------|------|---------------------------|-------|
| Edition | Aggregate | This device's entitlement: Free or Unlocked; cached locally, never re-locked by being offline | "licence", "tier", "plan" |
| Free | State | The default edition: Free limits apply | "trial", "lite" |
| Unlocked | State | Every feature available, for good, from one purchase | "premium", "pro", "subscribed" |
| Free limits | Value object | The table of what Free allows: 1 live match, 5 active players, newest 10 ended matches, most frames wins, alternate breaks; plus the list of paid features | "quota" |
| Paid feature | Concept | Anything outside the Free limits: templates, pause by hand, race to, sets, winner breaks, colours, head-to-head, stats, series, several live matches, lock screen | "premium feature" |
| Unlock | Command | Make the edition Unlocked after the App Store verifies the purchase | "activate" |
| Restore | Command | Unlock from a purchase the App Store already has on record | — |
| Revocation | Concept | The App Store withdrawing the purchase (refund, Family Sharing ended); returns the edition to Free | "cancel" |
| Upgrade offer | Concept | "Upgrade now" in place (templates, pause) or the generic "Upgrade once, forever, to unlock" screen | "paywall" (in the UI) |
| Benefits screen | Concept | The Upgrade menu item's page listing what unlocking gives; shown only while Free | — |

## Commands

| Command | Intent | Handled by |
|---------|--------|-----------|
| Purchase | Buy the unlock through the App Store | App Store adapter → Edition |
| RestorePurchases | Check the App Store for an existing unlock | App Store adapter → Edition |
| Unlock | Become Unlocked | Edition |
| Lock | Return to Free | Edition |
| ShowUpgradeOffer | Present the offer for a paid feature | Upgrade UI (no state) |

## Policies

| When | Then |
|------|------|
| App Store verifies the purchase (immediately or after Ask to Buy) | `Unlock` |
| App Store reports a revocation | `Lock` |
| `AppUnlocked` / `AppLocked` | hide / show the Upgrade menu item |

---

## Business Rules
- One non-consumable purchase; no subscription; Family Sharing on.
- Nothing unlocks until the App Store verifies the purchase.
- The edition is cached; offline never re-locks.
- The offer is never shown on launch or repeated as a pop-up.
- Upgrade never deletes or rewrites another context's data; Free limits hide, they don't remove.

## Aggregates
- `Edition` — Free or Unlocked (per device; raises `AppUnlocked`, `AppLocked`)

## External Dependencies

| External Context | Relationship | Translation Needed? |
|-----------------|--------------|---------------------|
| App Store (StoreKit) | Anti-corruption layer | Yes: transactions, Ask to Buy, revocations → Unlock / Lock |

## Team

| Role | Name |
|------|------|
| Domain Expert | Business owner |
| Tech Lead | Business owner |
| Team | Solo |

## Notes
- Generic: build the thinnest wrapper over StoreKit 2; don't add receipts servers or accounts.
- Enforcement lives with the data: Players (active count), Matches (live count, style, break rule, pause, templates, lock screen), Stats (newest 10, head-to-head, stats, series). See ADR-0011.
