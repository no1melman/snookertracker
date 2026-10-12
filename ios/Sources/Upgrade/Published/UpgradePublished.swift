import EventDispatch
import Foundation
import UpgradeDomain

// Upgrade's published language and open host (ADR-0011), for Matches, Players and Stats, which are
// conformist. Import only this module: the value objects below are Upgrade's own (one table, owned by
// Upgrade's domain), re-exposed here so downstream never imports UpgradeDomain.

/// Free or Unlocked.
public typealias EditionStatus = UpgradeDomain.EditionStatus
/// A feature outside the Free limits; touching one while Free opens the upgrade offer (S52).
public typealias PaidFeature = UpgradeDomain.PaidFeature
/// The Free-limits table: `FreeLimits.standard` (live matches 1, active players 5, visible ended
/// matches 10, most frames wins only, alternate breaks only).
public typealias FreeLimits = UpgradeDomain.FreeLimits
/// A match style as the Free limits name it; downstream maps its own style onto it.
public typealias MatchStyleKind = UpgradeDomain.MatchStyleKind
/// A break rule as the Free limits name it; downstream maps its own rule onto it.
public typealias BreakRuleKind = UpgradeDomain.BreakRuleKind
/// In place (templates, pause) or the generic screen.
public typealias UpgradeOfferPlacement = UpgradeDomain.UpgradeOfferPlacement

// MARK: - Open host: CurrentEdition

/// "Current edition and Free limits" (ADR-0011): synchronous, answered from the local cache, so it
/// works offline and never waits on the App Store. Read it before every guarded action; refuse with
/// the upgrade offer (S52) when `allows` is false or a `limits` count is reached. Never delete or
/// rewrite data to enforce a limit.
public protocol CurrentEdition: AnyObject, Sendable {
    var status: EditionStatus { get }
    /// The Free limits while Free; nil once Unlocked (no limits).
    var limits: FreeLimits? { get }
    /// Every paid feature once Unlocked; none while Free.
    func allows(_ feature: PaidFeature) -> Bool
}

public extension CurrentEdition {
    var limits: FreeLimits? { status == .free ? .standard : nil }
    func allows(_ feature: PaidFeature) -> Bool { status == .unlocked }
    var isUnlocked: Bool { status == .unlocked }
    var isFree: Bool { status == .free }
}

/// A `CurrentEdition` with a status set by hand: the test double for downstream tests, and the
/// default before the composition root hands the real one over. Flip `status` to simulate an unlock
/// or a revocation (dispatch `AppUnlockedPublished` / `AppLockedPublished` yourself if the code under
/// test reacts to them).
public final class FixedEdition: CurrentEdition, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: EditionStatus

    public init(_ status: EditionStatus = .free) { _status = status }

    public var status: EditionStatus {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }

    /// A fresh Free edition.
    public static var free: FixedEdition { FixedEdition(.free) }
    /// A fresh Unlocked edition: no limits, every feature allowed.
    public static var unlocked: FixedEdition { FixedEdition(.unlocked) }
}

// MARK: - Published events (Stage 2)

/// `AppUnlocked`: the device's edition became Unlocked (S49, S50). Hidden matches, colours, templates
/// and stats appear straight away; the benefits menu item is hidden (S53).
public struct AppUnlockedPublished: PublishedEvent, Hashable {
    public static let eventType = "Upgrade.AppUnlocked"
    public static let version = 1

    public let occurredAt: Date

    public init(occurredAt: Date) { self.occurredAt = occurredAt }
}

/// `AppLocked`: the device's edition went back to Free (S51). Nothing is deleted; Matches removes the
/// Live Activity (S47); the benefits menu item is shown again (S53).
public struct AppLockedPublished: PublishedEvent, Hashable {
    public static let eventType = "Upgrade.AppLocked"
    public static let version = 1

    public let occurredAt: Date

    public init(occurredAt: Date) { self.occurredAt = occurredAt }
}

// MARK: - Upgrade offer hook (S52)

/// A request to show the upgrade offer for `feature`: in place for templates and pause, the generic
/// "Upgrade once, forever, to unlock" screen otherwise. Raises nothing.
public struct UpgradeOfferRequest: Hashable, Sendable, Identifiable {
    public let feature: PaidFeature

    public init(_ feature: PaidFeature) { self.feature = feature }

    public var id: PaidFeature { feature }
    public var placement: UpgradeOfferPlacement { feature.offerPlacement }
}

/// What presentation calls when a guard refuses a paid feature: routes to Upgrade's
/// `ShowUpgradeOffer(PaidFeature)`. The composition root supplies the real one.
public typealias ShowUpgradeOfferAction = @MainActor @Sendable (PaidFeature) -> Void

/// A guard's refusal because the edition is Free: catch it in presentation and call
/// `ShowUpgradeOfferAction` with `feature`. A context may use its own error instead.
public struct UpgradeRequired: Error, Hashable, Sendable, LocalizedError {
    public let feature: PaidFeature

    public init(_ feature: PaidFeature) { self.feature = feature }

    public var errorDescription: String? { "Upgrade once, forever, to unlock this." }
}
