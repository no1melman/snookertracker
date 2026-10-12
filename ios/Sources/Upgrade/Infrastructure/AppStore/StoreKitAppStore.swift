import Foundation
import UpgradeApplication
import UpgradeDomain

/// How one App Store transaction reads to Upgrade (ADR-0011): only a verified transaction for the
/// unlock counts; a verified one with a revocation date (a refund, Family Sharing ending) locks.
/// Kept free of StoreKit types so the rule is testable without the App Store.
enum TransactionReading {
    static func update(isUnlock: Bool, isVerified: Bool, isRevoked: Bool) -> AppStoreTransactionUpdate? {
        guard isUnlock, isVerified else { return nil }
        return isRevoked ? .revoked : .verified
    }
}

/// Orders the launch check against live transaction updates: the launch result is delivered only if
/// no live update came first.
final class LaunchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var sawLive = false
    private let continuation: AsyncStream<AppStoreTransactionUpdate>.Continuation

    init(_ continuation: AsyncStream<AppStoreTransactionUpdate>.Continuation) { self.continuation = continuation }

    func yieldLive(_ update: AppStoreTransactionUpdate) {
        lock.withLock {
            sawLive = true
            continuation.yield(update)
        }
    }

    func yieldLaunch(_ update: AppStoreTransactionUpdate) {
        lock.withLock {
            guard !sawLive else { return }
            continuation.yield(update)
        }
    }
}

#if canImport(StoreKit)
import StoreKit

/// `AppStorePort` over StoreKit 2: the App Store → Upgrade anti-corruption layer (ADR-0011, spec 028).
/// The only file in the app that imports StoreKit; no StoreKit type crosses the port.
///
/// Create it once at launch: `transactionUpdates` starts listening to `Transaction.updates` straight
/// away (so an Ask to Buy approval or a refund that happened while the app was closed still
/// arrives), and checks the current entitlement once. A launch that finds nothing on record reports
/// nothing, so an offline device keeps its cached edition; only a revocation ever locks.
public final class StoreKitAppStore: AppStorePort, Sendable {
    private let product: UnlockProductId
    public let transactionUpdates: AsyncStream<AppStoreTransactionUpdate>

    public init(product: UnlockProductId = .fullVersion) {
        self.product = product
        let id = product.value
        transactionUpdates = AsyncStream { continuation in
            // Listen first, check the launch state alongside. A live update is newer than the launch
            // check, so once one has been delivered the launch result is dropped: a stale launch
            // "verified" can never undo a revocation that arrived meanwhile.
            let gate = LaunchGate(continuation)
            let updates = Task.detached {
                for await result in Transaction.updates {
                    if let update = await Self.read(result, unlock: id) { gate.yieldLive(update) }
                }
                continuation.finish()
            }
            let launch = Task.detached {
                if let update = await Self.launchState(unlock: id) { gate.yieldLaunch(update) }
            }
            continuation.onTermination = { _ in
                updates.cancel()
                launch.cancel()
            }
        }
    }

    // MARK: AppStorePort

    public func purchase(_ product: UnlockProductId) async -> PurchaseOutcome {
        guard let storeProduct = try? await Product.products(for: [product.value]).first else { return .failed }
        do {
            return await Self.outcome(of: try await storeProduct.purchase(), unlock: product.value)
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed
        }
    }

    /// purchased only for a verified, unrevoked unlock transaction (then finished); Ask to Buy →
    /// pending; backing out → cancelled.
    static func outcome(of result: Product.PurchaseResult, unlock id: String) async -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            guard let transaction = verifiedUnlock(verification, unlock: id) else { return .failed }
            await transaction.finish()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .failed
        }
    }

    /// `AppStore.sync()`, then the current entitlements. When the sync can't complete (offline, or
    /// the sign-in was dismissed) an entitlement already on the device still restores; otherwise the
    /// App Store couldn't be reached.
    public func restore() async throws -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            guard await Self.isEntitled(unlock: product.value) else { throw AppStoreUnavailable() }
            return true
        }
        return await Self.isEntitled(unlock: product.value)
    }

    public func displayPrice(_ product: UnlockProductId) async -> String? {
        try? await Product.products(for: [product.value]).first?.displayPrice
    }

    // MARK: Translation

    /// A transaction update as Upgrade sees it. Verified transactions are finished; unverified ones
    /// are ignored (never unlock) and left unfinished.
    private static func read(_ result: VerificationResult<Transaction>, unlock id: String) async -> AppStoreTransactionUpdate? {
        guard case .verified(let transaction) = result else { return nil }
        await transaction.finish()
        return TransactionReading.update(
            isUnlock: transaction.productID == id, isVerified: true, isRevoked: transaction.revocationDate != nil)
    }

    /// At launch: a verified current entitlement → verified; else a verified latest transaction that
    /// was revoked → revoked; nothing on record → nothing (keeps the cached edition offline).
    private static func launchState(unlock id: String) async -> AppStoreTransactionUpdate? {
        if await isEntitled(unlock: id) { return .verified }
        guard case .verified(let latest)? = await Transaction.latest(for: id) else { return nil }
        return latest.revocationDate != nil ? .revoked : nil
    }

    private static func isEntitled(unlock id: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == id,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    private static func verifiedUnlock(_ result: VerificationResult<Transaction>, unlock id: String) -> Transaction? {
        guard case .verified(let transaction) = result,
              TransactionReading.update(
                isUnlock: transaction.productID == id, isVerified: true,
                isRevoked: transaction.revocationDate != nil) == .verified
        else { return nil }
        return transaction
    }
}
#endif
