import Foundation
import UpgradeDomain

// MARK: - Persistence port (spec 023)

/// `EditionStore`: the single edition per device, cached locally so it survives offline launches.
public protocol EditionStore: Sendable {
    /// The cached edition; `Edition.initial` (Free) when none was ever saved.
    func get() throws -> Edition
    func save(_ edition: Edition) throws
}

// MARK: - App Store port (anti-corruption layer, ADR-0011)

/// What the App Store said about a purchase attempt (S49).
public enum PurchaseOutcome: String, Hashable, Sendable {
    /// Verified: unlock now.
    case purchased
    /// Ask to Buy: nothing unlocks yet; the approval arrives later through `transactionUpdates`.
    case pending
    /// The scorer backed out: nothing changes.
    case cancelled
    /// The payment failed (or the App Store couldn't be reached): nothing changes.
    case failed
}

/// A transaction update from the App Store, at launch or while running (S49, S51).
public enum AppStoreTransactionUpdate: String, Hashable, Sendable {
    /// A verified unlock: an Ask to Buy approval, a purchase on another family device, a restore.
    case verified
    /// The unlock was revoked: a refund, or Family Sharing ending.
    case revoked
}

/// The App Store couldn't be reached (S50 offline).
public struct AppStoreUnavailable: Error, Hashable, Sendable {
    public init() {}
}

/// `AppStorePort`: the App Store as Upgrade sees it. The StoreKit adapter (spec 028) implements it;
/// no StoreKit type crosses it.
public protocol AppStorePort: Sendable {
    /// Runs the App Store purchase of `product` and reports the outcome; only `purchased` is verified.
    func purchase(_ product: UnlockProductId) async -> PurchaseOutcome
    /// Whether the unlock is on record (including through Family Sharing).
    /// Throws `AppStoreUnavailable` when the App Store can't be reached.
    func restore() async throws -> Bool
    /// Verified unlocks and revocations, delivered at launch and while running.
    var transactionUpdates: AsyncStream<AppStoreTransactionUpdate> { get }
    /// The localised price of `product` for the benefits screen (S53); nil when unknown or offline.
    func displayPrice(_ product: UnlockProductId) async -> String?
}
