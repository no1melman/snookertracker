import Foundation

/// The `Edition` aggregate root: this device's entitlement, Free or Unlocked (ADR-0010). One per device.
///
/// Invariant: the status changes only through `unlock` and `lock`, never because a check failed or the
/// device is offline. `unlock` is called only for a purchase the App Store verified (the adapter's job).
///
/// Transitions are non-mutating: each returns a new `Edition`. Both are idempotent: unlocking an
/// Unlocked edition, or locking a Free one, returns it unchanged and raises nothing.
public struct Edition: Equatable, Sendable {
    public private(set) var status: EditionStatus
    /// Raised since load; the application layer dispatches them after the save.
    public private(set) var domainEvents: [EditionEvent]

    private init(status: EditionStatus, domainEvents: [EditionEvent]) {
        self.status = status
        self.domainEvents = domainEvents
    }

    // MARK: Factory

    /// A device that never bought the unlock: Free.
    public static let initial = Edition(status: .free, domainEvents: [])

    /// Rebuilds the edition from the local cache. Runs no rules and raises no events.
    public static func reconstitute(status: EditionStatus) -> Edition {
        Edition(status: status, domainEvents: [])
    }

    // MARK: Behaviours

    /// Becomes Unlocked after a verified purchase, approval or restore; raises `AppUnlocked`.
    public func unlock(at now: Date) -> Edition {
        transition(to: .unlocked, raising: .unlocked(AppUnlocked(occurredAt: now)))
    }

    /// Returns to Free after a revocation; raises `AppLocked`. Deletes nothing anywhere.
    public func lock(at now: Date) -> Edition {
        transition(to: .free, raising: .locked(AppLocked(occurredAt: now)))
    }

    // MARK: Queries

    /// Whether a paid feature may be used: every paid feature once Unlocked, none while Free.
    public func allows(_ feature: PaidFeature) -> Bool { status == .unlocked }

    /// The Free limits, or nil once Unlocked.
    public var limits: FreeLimits? { status == .free ? .standard : nil }

    public func clearingDomainEvents() -> Edition { Edition(status: status, domainEvents: []) }

    private func transition(to next: EditionStatus, raising event: EditionEvent) -> Edition {
        guard status.canTransition(to: next) else { return self }
        return Edition(status: next, domainEvents: domainEvents + [event])
    }
}
