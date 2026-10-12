import EventDispatch
import Foundation
import SQLiteSupport
import Testing
import UpgradeApplication
import UpgradeDomain
import UpgradeInfrastructure
import UpgradePublished

// Outside-in: the real use cases over the real SQLite edition store and a fake App Store.

/// Records Upgrade's published events, in order.
private final class Published: @unchecked Sendable {
    private(set) var events: [String] = []

    init(_ dispatcher: EventDispatcher) {
        dispatcher.subscribe(AppUnlockedPublished.self) { [unowned self] _ in events.append(AppUnlockedPublished.eventType) }
        dispatcher.subscribe(AppLockedPublished.self) { [unowned self] _ in events.append(AppLockedPublished.eventType) }
    }
}

/// One launch of the app's Upgrade context on `db`.
@MainActor
private struct Launch {
    let edition: StoredEdition
    let upgrade: UpgradeUseCases
    let appStore: FakeAppStore
    let published: Published

    init(_ db: SQLiteDatabase, appStore: FakeAppStore = FakeAppStore()) throws {
        let dispatcher = EventDispatcher()
        edition = try StoredEdition(store: SQLiteEditionStore(db: db))
        upgrade = UpgradeUseCases(store: edition, appStore: appStore, dispatcher: dispatcher)
        self.appStore = appStore
        published = Published(dispatcher)
    }

    /// Delivers the fake's queued transaction updates, then stops listening.
    func drainUpdates() async {
        appStore.finishUpdates()
        await upgrade.listenForTransactionUpdates()
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "upgrade-\(UUID().uuidString).sqlite")
}

@MainActor
@Suite struct UpgradeIntegrationTests {
    // MARK: PurchaseUnlock (S49)

    @Test func aVerifiedPurchaseUnlocksAndIsCached() async throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try Launch(db, appStore: FakeAppStore(purchaseOutcome: .purchased))
        #expect(app.edition.status == .free)

        #expect(try await app.upgrade.purchaseUnlock() == .purchased)

        #expect(app.edition.status == .unlocked)
        #expect(app.edition.limits == nil)
        #expect(PaidFeature.allCases.allSatisfy(app.edition.allows))
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
        #expect(app.appStore.purchases == [.fullVersion])
        #expect(try SQLiteEditionStore(db: db).get().status == .unlocked)

        // Buying (or being told) again changes nothing and raises nothing.
        try await app.upgrade.purchaseUnlock()
        try app.upgrade.handleAppStoreUpdate(.verified)
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
    }

    @Test func aPendingPurchaseUnlocksOnlyWhenApprovedLater() async throws {
        let app = try Launch(.inMemory(), appStore: FakeAppStore(purchaseOutcome: .pending))

        #expect(try await app.upgrade.purchaseUnlock() == .pending)
        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)

        app.appStore.approvePending()
        await app.drainUpdates()
        #expect(app.edition.status == .unlocked)
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
    }

    @Test func anAskToBuyApprovalAfterARestartUnlocks() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let app = try Launch(SQLiteDatabase(url: url), appStore: FakeAppStore(purchaseOutcome: .pending))
            #expect(try await app.upgrade.purchaseUnlock() == .pending)
            #expect(app.edition.status == .free)
        }
        // Relaunch: a new database connection, store and App Store; the approval arrives as an update.
        let relaunched = try Launch(SQLiteDatabase(url: url))
        #expect(relaunched.edition.status == .free)
        relaunched.appStore.approvePending()
        await relaunched.drainUpdates()
        #expect(relaunched.edition.status == .unlocked)
        #expect(relaunched.published.events == ["Upgrade.AppUnlocked"])

        let again = try Launch(SQLiteDatabase(url: url))
        #expect(again.edition.status == .unlocked)
    }

    @Test(arguments: [PurchaseOutcome.cancelled, .failed])
    func aCancelledOrFailedPurchaseChangesNothing(outcome: PurchaseOutcome) async throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try Launch(db, appStore: FakeAppStore(purchaseOutcome: outcome))

        #expect(try await app.upgrade.purchaseUnlock() == outcome)

        #expect(app.edition.status == .free)
        #expect(app.edition.limits == .standard)
        #expect(app.published.events.isEmpty)
        #expect(try SQLiteEditionStore(db: db).get() == .initial)
    }

    // MARK: RestorePurchases (S50)

    @Test func restoreUnlocksWhenThePurchaseIsOnRecord() async throws {
        let app = try Launch(.inMemory(), appStore: FakeAppStore(unlockOnRecord: true))

        #expect(try await app.upgrade.restorePurchases() == .unlocked)

        #expect(app.edition.status == .unlocked)
        #expect(app.published.events == ["Upgrade.AppUnlocked"])
    }

    @Test func restoreWithNothingOnRecordStaysFree() async throws {
        let app = try Launch(.inMemory(), appStore: FakeAppStore(unlockOnRecord: false))

        #expect(try await app.upgrade.restorePurchases() == .nothingToRestore)

        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)
    }

    @Test func restoreOfflineStaysFree() async throws {
        let app = try Launch(.inMemory(), appStore: FakeAppStore(unlockOnRecord: true, reachable: false))

        #expect(try await app.upgrade.restorePurchases() == .appStoreUnavailable)

        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)
    }

    // MARK: HandleAppStoreUpdate (S51)

    @Test func aRevocationLocksAndPublishesAppLocked() async throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try Launch(db, appStore: FakeAppStore(purchaseOutcome: .purchased))
        try await app.upgrade.purchaseUnlock()

        app.appStore.revoke()
        await app.drainUpdates()

        #expect(app.edition.status == .free)
        #expect(app.edition.limits == .standard)
        #expect(app.published.events == ["Upgrade.AppUnlocked", "Upgrade.AppLocked"])
        #expect(try SQLiteEditionStore(db: db).get().status == .free)
    }

    @Test func aRevocationWhileFreeRaisesNothing() throws {
        let app = try Launch(.inMemory())
        try app.upgrade.handleAppStoreUpdate(.revoked)
        #expect(app.edition.status == .free)
        #expect(app.published.events.isEmpty)
    }

    // MARK: CurrentEdition (offline, cache)

    @Test func anOfflineLaunchKeepsTheCachedEdition() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let app = try Launch(SQLiteDatabase(url: url), appStore: FakeAppStore(purchaseOutcome: .purchased))
            try await app.upgrade.purchaseUnlock()
        }
        // Relaunch offline: the App Store can't be reached, yet the edition stays Unlocked.
        let offline = try Launch(SQLiteDatabase(url: url), appStore: FakeAppStore(reachable: false))
        #expect(offline.edition.status == .unlocked)
        #expect(try await offline.upgrade.restorePurchases() == .appStoreUnavailable)
        #expect(try await offline.upgrade.purchaseUnlock() == .failed)
        #expect(await offline.upgrade.displayPrice() == nil)
        await offline.drainUpdates()
        #expect(offline.edition.status == .unlocked)
        #expect(offline.published.events.isEmpty)
    }

    @Test func theBenefitsScreenPriceComesFromTheAppStore() async throws {
        let app = try Launch(.inMemory(), appStore: FakeAppStore(price: "£2.99"))
        #expect(await app.upgrade.displayPrice() == "£2.99")
    }

    // MARK: ShowUpgradeOffer (S52)

    @Test func theOfferIsInPlaceForTemplatesAndPauseAndGenericOtherwise() throws {
        let app = try Launch(.inMemory())
        let show = ShowUpgradeOffer(edition: app.edition)

        #expect(show(.templates)?.placement == .inPlace)
        #expect(show(.manualPause)?.placement == .inPlace)
        #expect(show(.stats)?.placement == .genericScreen)
        #expect(show(.extraPlayers) == UpgradeOfferRequest(.extraPlayers))
        #expect(app.published.events.isEmpty)
    }

    @Test func noOfferOnceUnlocked() async throws {
        let app = try Launch(.inMemory())
        try await app.upgrade.purchaseUnlock()
        let show = ShowUpgradeOffer(edition: app.edition)
        #expect(PaidFeature.allCases.allSatisfy { show($0) == nil })
    }

    // MARK: FixedEdition (the downstream test double)

    @Test func theFixedEditionCanBeFlipped() {
        let edition = FixedEdition(.free)
        #expect(edition.limits == .standard)
        #expect(!edition.allows(.stats))
        edition.status = .unlocked
        #expect(edition.limits == nil)
        #expect(edition.allows(.stats))
        #expect(FixedEdition.unlocked.isUnlocked)
        #expect(FixedEdition.free.isFree)
    }
}
