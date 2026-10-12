import Foundation
import UpgradeApplication
import UpgradeDomain

/// An in-memory `AppStorePort` for tests and previews; the app runs `StoreKitAppStore` (spec 028).
///
/// A `purchased` purchase and an approved Ask to Buy both put the unlock on record, so a later
/// restore finds it. `transactionUpdates` can be iterated once per instance (like StoreKit's).
public final class FakeAppStore: AppStorePort, @unchecked Sendable {
    private let lock = NSLock()
    private var _purchaseOutcome: PurchaseOutcome
    private var _unlockOnRecord: Bool
    private var _reachable: Bool
    private var _price: String?
    private var _purchases: [UnlockProductId] = []
    private let continuation: AsyncStream<AppStoreTransactionUpdate>.Continuation
    public let transactionUpdates: AsyncStream<AppStoreTransactionUpdate>

    public init(
        purchaseOutcome: PurchaseOutcome = .purchased, unlockOnRecord: Bool = false,
        reachable: Bool = true, price: String? = "£2.99"
    ) {
        _purchaseOutcome = purchaseOutcome
        _unlockOnRecord = unlockOnRecord
        _reachable = reachable
        _price = price
        (transactionUpdates, continuation) = AsyncStream.makeStream()
    }

    /// What the next `purchase` returns.
    public var purchaseOutcome: PurchaseOutcome {
        get { lock.withLock { _purchaseOutcome } }
        set { lock.withLock { _purchaseOutcome = newValue } }
    }

    /// Whether `restore` finds the unlock.
    public var unlockOnRecord: Bool {
        get { lock.withLock { _unlockOnRecord } }
        set { lock.withLock { _unlockOnRecord = newValue } }
    }

    /// False simulates being offline: `restore` throws, `purchase` fails, no price.
    public var reachable: Bool {
        get { lock.withLock { _reachable } }
        set { lock.withLock { _reachable = newValue } }
    }

    /// Every product a purchase was attempted for.
    public var purchases: [UnlockProductId] { lock.withLock { _purchases } }

    // MARK: AppStorePort

    public func purchase(_ product: UnlockProductId) async -> PurchaseOutcome {
        lock.withLock {
            _purchases.append(product)
            guard _reachable else { return .failed }
            if _purchaseOutcome == .purchased { _unlockOnRecord = true }
            return _purchaseOutcome
        }
    }

    public func restore() async throws -> Bool {
        let (reachable, onRecord) = lock.withLock { (_reachable, _unlockOnRecord) }
        guard reachable else { throw AppStoreUnavailable() }
        return onRecord
    }

    public func displayPrice(_ product: UnlockProductId) async -> String? {
        lock.withLock { _reachable ? _price : nil }
    }

    // MARK: Driving updates

    /// Ask to Buy approved (or a purchase made elsewhere): the unlock goes on record and a verified
    /// update is delivered.
    public func approvePending() {
        unlockOnRecord = true
        send(.verified)
    }

    /// A refund or Family Sharing ending: the unlock leaves the record and a revocation is delivered.
    public func revoke() {
        unlockOnRecord = false
        send(.revoked)
    }

    public func send(_ update: AppStoreTransactionUpdate) { continuation.yield(update) }

    /// Ends `transactionUpdates`, so a listener returns.
    public func finishUpdates() { continuation.finish() }
}
