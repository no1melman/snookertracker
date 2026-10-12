import EventDispatch
import Foundation
import SQLiteSupport
import Testing
import UpgradeApplication
import UpgradeInfrastructure
import UpgradePublished

// S53: the hub's benefits menu item, over the real use cases, the real SQLite edition store and a fake
// App Store. It follows `AppUnlocked` / `AppLocked` as they are dispatched.

@MainActor
@Suite struct BenefitsMenuItemTests {
    private struct App {
        let edition: StoredEdition
        let upgrade: UpgradeUseCases
        let menuItem: BenefitsMenuItem

        @MainActor init(_ db: SQLiteDatabase, _ appStore: FakeAppStore) throws {
            let dispatcher = EventDispatcher()
            edition = try StoredEdition(store: SQLiteEditionStore(db: db))
            upgrade = UpgradeUseCases(store: edition, appStore: appStore, dispatcher: dispatcher)
            menuItem = BenefitsMenuItem(edition: edition)
            menuItem.subscribe(to: dispatcher)
        }
    }

    @Test func hiddenOnAppUnlockedAndShownOnAppLocked() async throws {
        let db = try SQLiteDatabase.inMemory()
        let appStore = FakeAppStore(purchaseOutcome: .purchased)
        let app = try App(db, appStore)
        #expect(app.menuItem.isVisible)

        try await app.upgrade.purchaseUnlock()
        #expect(!app.menuItem.isVisible)

        // Revoked (a refund): AppLocked brings it back.
        try app.upgrade.handleAppStoreUpdate(.revoked)
        #expect(app.edition.isFree)
        #expect(app.menuItem.isVisible)

        // Restored: AppUnlocked hides it again.
        #expect(try await app.upgrade.restorePurchases() == .unlocked)
        #expect(!app.menuItem.isVisible)
    }

    @Test func followsTheCachedEditionAtLaunch() async throws {
        let db = try SQLiteDatabase.inMemory()
        try await App(db, FakeAppStore(purchaseOutcome: .purchased)).upgrade.purchaseUnlock()

        let relaunched = try App(db, FakeAppStore(reachable: false))
        #expect(!relaunched.menuItem.isVisible)
    }

    @Test func nothingChangesWhenNothingUnlocks() async throws {
        let app = try App(.inMemory(), FakeAppStore(purchaseOutcome: .cancelled))
        try await app.upgrade.purchaseUnlock()
        #expect(try await app.upgrade.restorePurchases() == .nothingToRestore)
        #expect(app.menuItem.isVisible)
    }
}
