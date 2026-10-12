#if canImport(StoreKitTest)
import EventDispatch
import Foundation
import SQLiteSupport
import StoreKit
import StoreKitTest
import Testing
import UpgradeApplication
import UpgradeDomain
@testable import UpgradeInfrastructure
import UpgradePublished

// Outside-in over StoreKitTest's local App Store (StoreKit/SnookerTracker.storekit): the real use
// cases, the real SQLite edition store and the real StoreKit adapter. Serialized: one test session
// is process-wide StoreKit state.
//
// Not a SwiftPM target: SKTestSession needs an app host to reach the StoreKit test service, so
// `swift test` can't run it (SKServiceErrorDomain 2). It is the app-hosted `SnookerTrackerStoreKitTests`
// bundle in project.yml: `xcodebuild test -scheme SnookerTracker -destination 'platform=iOS Simulator,…'`.

/// Records Upgrade's published events, in order.
private final class Published: @unchecked Sendable {
    private(set) var events: [String] = []

    init(_ dispatcher: EventDispatcher) {
        dispatcher.subscribe(AppUnlockedPublished.self) { [unowned self] _ in events.append(AppUnlockedPublished.eventType) }
        dispatcher.subscribe(AppLockedPublished.self) { [unowned self] _ in events.append(AppLockedPublished.eventType) }
    }
}

/// One launch of Upgrade over `db` with the StoreKit adapter, listening from the start (as the
/// composition root does).
@MainActor
private final class Launch {
    let edition: StoredEdition
    let upgrade: UpgradeUseCases
    let appStore: StoreKitAppStore
    let published: Published
    private var listener: Task<Void, Never>?

    init(_ db: SQLiteDatabase) throws {
        let dispatcher = EventDispatcher()
        edition = try StoredEdition(store: SQLiteEditionStore(db: db))
        appStore = StoreKitAppStore()
        upgrade = UpgradeUseCases(store: edition, appStore: appStore, dispatcher: dispatcher)
        published = Published(dispatcher)
        listener = Task { [upgrade] in await upgrade.listenForTransactionUpdates() }
    }

    func stop() { listener?.cancel() }

    /// Waits (up to `seconds`) until `condition` holds; returns whether it did.
    func eventually(within seconds: Double = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

/// The configuration file the app scheme also uses, found from this source file (ios/StoreKit/).
private let configurationURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "StoreKit/SnookerTracker.storekit")

private func freshSession() throws -> SKTestSession {
    let session = try SKTestSession(contentsOf: configurationURL)
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    return session
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "upgrade-storekit-\(UUID().uuidString).sqlite")
}

private func unlockTransactions(_ session: SKTestSession) -> [SKTestTransaction] {
    session.allTransactions().filter { $0.productIdentifier == UnlockProductId.fullVersion.value }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct StoreKitAppStoreTests {
    // MARK: Purchase (S49)

    @Test func aVerifiedPurchaseUnlocks() async throws {
        let session = try freshSession()
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(try await app.upgrade.purchaseUnlock() == .purchased)

        #expect(app.edition.status == .unlocked)
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
        #expect(unlockTransactions(session).count == 1)
    }

    @Test func askToBuyIsPendingThenUnlocksWhenApprovedAfterARestart() async throws {
        let session = try freshSession()
        session.askToBuyEnabled = true
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let app = try Launch(SQLiteDatabase(url: url))
            #expect(try await app.upgrade.purchaseUnlock() == .pending)
            #expect(app.edition.status == .free)
            #expect(app.published.events.isEmpty)
            app.stop()
        }

        // Relaunch, then the parent approves: the update arrives through Transaction.updates.
        let relaunched = try Launch(SQLiteDatabase(url: url))
        defer { relaunched.stop() }
        #expect(relaunched.edition.status == .free)
        let pending = try #require(unlockTransactions(session).first { $0.pendingAskToBuyConfirmation })
        // The parent approves a moment after launch (not within the listener's first milliseconds).
        try await Task.sleep(for: .milliseconds(500))
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        #expect(await relaunched.eventually { relaunched.edition.status == .unlocked })
        #expect(relaunched.published.events == ["Upgrade.AppUnlocked"])
    }

    /// StoreKitTest can't back out of a payment sheet with dialogs off (a simulated `userCancelled`
    /// surfaces as `.unknown`), so the cancel is StoreKit's own `.userCancelled` result, translated.
    @Test func aCancelledPurchaseIsCancelled() async throws {
        _ = try freshSession()
        let id = UnlockProductId.fullVersion.value
        #expect(await StoreKitAppStore.outcome(of: .userCancelled, unlock: id) == .cancelled)
        #expect(await StoreKitAppStore.outcome(of: .pending, unlock: id) == .pending)
    }

    @Test func aFailedPurchaseChangesNothing() async throws {
        let session = try freshSession()
        try await session.setSimulatedError(.purchase(.purchaseNotAllowed), forAPI: .purchase)
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(try await app.upgrade.purchaseUnlock() == .failed)
        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }

    @Test func aPurchaseThatFailsVerificationNeverUnlocks() async throws {
        let session = try freshSession()
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(try await app.upgrade.purchaseUnlock() == .failed)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)
        try await session.setSimulatedError(nil, forAPI: .verification)
    }

    // MARK: Restore (S50)

    @Test func restoreWithAPurchaseOnRecordUnlocks() async throws {
        let session = try freshSession()
        _ = try await session.buyProduct(identifier: UnlockProductId.fullVersion.value)
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(try await app.upgrade.restorePurchases() == .unlocked)
        #expect(app.edition.status == .unlocked)
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
    }

    @Test func restoreWithoutAPurchaseFindsNothing() async throws {
        _ = try freshSession()
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(try await app.upgrade.restorePurchases() == .nothingToRestore)
        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)
    }

    @Test func restoreOfflineWithoutAPurchaseCouldntReachTheAppStore() async throws {
        let session = try freshSession()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(try await app.upgrade.restorePurchases() == .appStoreUnavailable)
        #expect(app.edition.status == .free)
        try await session.setSimulatedError(nil, forAPI: .appStoreSync)
    }

    // MARK: Revocation (S51)

    @Test func aRefundLocks() async throws {
        let session = try freshSession()
        let app = try Launch(.inMemory())
        defer { app.stop() }
        #expect(try await app.upgrade.purchaseUnlock() == .purchased)
        #expect(app.edition.status == .unlocked)

        let bought = try #require(unlockTransactions(session).first)
        // Let the launch's entitlement check settle, so the refund is a later Transaction.updates event.
        try await Task.sleep(for: .milliseconds(500))
        try session.refundTransaction(identifier: bought.identifier)

        #expect(await app.eventually { app.edition.status == .free })
        #expect(app.published.events == ["Upgrade.AppUnlocked", "Upgrade.AppLocked"])
    }

    // MARK: Launch

    @Test func aLaunchWithThePurchaseOnRecordUnlocks() async throws {
        let session = try freshSession()
        _ = try await session.buyProduct(identifier: UnlockProductId.fullVersion.value)
        let app = try Launch(.inMemory())
        defer { app.stop() }

        #expect(await app.eventually { app.edition.status == .unlocked })
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
    }

    @Test func anOfflineLaunchKeepsTheCachedEdition() async throws {
        let session = try freshSession()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let db = try SQLiteDatabase.inMemory()
        try SQLiteEditionStore(db: db).save(Edition.initial.unlock(at: Date()))

        // Nothing on record as far as this device can tell: no update, no lock.
        let app = try Launch(db)
        defer { app.stop() }
        try? await Task.sleep(for: .seconds(1))
        #expect(app.edition.status == .unlocked)
        #expect(app.published.events.isEmpty)
        #expect(await app.upgrade.displayPrice() == nil)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
    }

    // MARK: Benefits screen (S53)

    @Test func thePriceIsLocalised() async throws {
        _ = try freshSession()
        let app = try Launch(.inMemory())
        defer { app.stop() }

        let price = try #require(await app.upgrade.displayPrice())
        #expect(price.contains("2.99"))
    }
}
#endif
