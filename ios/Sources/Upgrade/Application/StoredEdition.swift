import Foundation
import UpgradeDomain
import UpgradePublished

/// The `CurrentEdition` open host (ADR-0011), served from the `EditionStore`.
///
/// Reads the stored edition once at launch and keeps it in memory; every save goes through here, so
/// the answer is always the cached edition. It never waits on the App Store, and being offline never
/// changes it. The use cases save through this object (it is also an `EditionStore`).
public final class StoredEdition: CurrentEdition, EditionStore, @unchecked Sendable {
    private let store: any EditionStore
    private let lock = NSLock()
    private var cached: Edition

    public init(store: any EditionStore) throws {
        self.store = store
        cached = try store.get()
    }

    // MARK: CurrentEdition

    public var status: EditionStatus { lock.withLock { cached.status } }
    public var limits: FreeLimits? { lock.withLock { cached.limits } }
    public func allows(_ feature: PaidFeature) -> Bool { lock.withLock { cached.allows(feature) } }

    // MARK: EditionStore

    public func get() throws -> Edition { lock.withLock { cached } }

    public func save(_ edition: Edition) throws {
        try lock.withLock {
            try store.save(edition)
            cached = edition.clearingDomainEvents()
        }
    }
}
