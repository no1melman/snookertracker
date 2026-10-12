import EventDispatch
import Foundation
import UpgradeDomain
import UpgradePublished

/// What `RestorePurchases` found (S50).
public enum RestoreOutcome: String, Hashable, Sendable {
    /// The unlock is on record: the edition is Unlocked.
    case unlocked
    /// "Nothing to restore": stays as it is.
    case nothingToRestore
    /// "Couldn't reach the App Store": stays as it is.
    case appStoreUnavailable
}

/// Upgrade's command side (spec 023): `PurchaseUnlock`, `RestorePurchases` and `HandleAppStoreUpdate`.
/// Each change is load → `unlock` / `lock` → save → dispatch `AppUnlocked` / `AppLocked`. Only a
/// verified answer from the App Store ever unlocks; only a revocation ever locks.
@MainActor
public final class UpgradeUseCases {
    private let store: any EditionStore
    private let appStore: any AppStorePort
    private let dispatcher: EventDispatcher
    private let product: UnlockProductId
    private let now: @Sendable () -> Date
    /// The last failure while handling a transaction update (logged, never thrown into a listener).
    public private(set) var lastError: (any Error)?

    public init(
        store: any EditionStore, appStore: any AppStorePort, dispatcher: EventDispatcher,
        product: UnlockProductId = .fullVersion, now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.appStore = appStore
        self.dispatcher = dispatcher
        self.product = product
        self.now = now
    }

    // MARK: PurchaseUnlock (S49)

    /// purchased → unlock; pending → nothing yet (the approval arrives through `HandleAppStoreUpdate`);
    /// cancelled or failed → nothing changes.
    @discardableResult
    public func purchaseUnlock() async throws -> PurchaseOutcome {
        let outcome = await appStore.purchase(product)
        if outcome == .purchased { try unlock() }
        return outcome
    }

    // MARK: RestorePurchases (S50)

    /// The unlock on record → unlock; none → "Nothing to restore"; offline → stays as it is.
    @discardableResult
    public func restorePurchases() async throws -> RestoreOutcome {
        let onRecord: Bool
        do {
            onRecord = try await appStore.restore()
        } catch {
            return .appStoreUnavailable
        }
        guard onRecord else { return .nothingToRestore }
        try unlock()
        return .unlocked
    }

    // MARK: HandleAppStoreUpdate (S49, S51)

    /// verified → unlock; revoked → lock.
    public func handleAppStoreUpdate(_ update: AppStoreTransactionUpdate) throws {
        switch update {
        case .verified: try unlock()
        case .revoked: try commit(try store.get().lock(at: now()))
        }
    }

    /// Handles every App Store transaction update until the stream ends. Start once at launch.
    public func listenForTransactionUpdates() async {
        for await update in appStore.transactionUpdates {
            do { try handleAppStoreUpdate(update) } catch { lastError = error }
        }
    }

    // MARK: Benefits screen (S53)

    /// The localised price of the unlock, from the App Store; nil when unknown or offline.
    public func displayPrice() async -> String? {
        await appStore.displayPrice(product)
    }

    // MARK: Plumbing

    private func unlock() throws {
        try commit(try store.get().unlock(at: now()))
    }

    /// save → dispatch. Idempotent transitions raise nothing, so nothing is saved or dispatched.
    private func commit(_ edition: Edition) throws {
        guard !edition.domainEvents.isEmpty else { return }
        try store.save(edition)
        dispatcher.dispatch(edition.domainEvents.map(EditionEventWire.published))
    }
}

/// `ShowUpgradeOffer(PaidFeature)` (S52): where the offer for a touched paid feature appears, in place
/// (templates, pause) or the generic screen. Nil once Unlocked (nothing to offer). Raises nothing.
public struct ShowUpgradeOffer: Sendable {
    private let edition: any CurrentEdition

    public init(edition: any CurrentEdition) { self.edition = edition }

    public func callAsFunction(_ feature: PaidFeature) -> UpgradeOfferRequest? {
        edition.allows(feature) ? nil : UpgradeOfferRequest(feature)
    }
}

/// Edition events in Upgrade's published language.
enum EditionEventWire {
    static func published(_ event: EditionEvent) -> any PublishedEvent {
        switch event {
        case .unlocked(let e): AppUnlockedPublished(occurredAt: e.occurredAt)
        case .locked(let e): AppLockedPublished(occurredAt: e.occurredAt)
        }
    }
}
