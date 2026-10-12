import EventDispatch
import Foundation
import SQLiteSupport
import Testing
import UpgradeApplication
import UpgradeInfrastructure
import UpgradePresentation
import UpgradePublished

// The benefits screen's state (S49, S50, S53) over the real use cases, the real SQLite edition store
// and a fake App Store.

@MainActor
private struct Screen {
    let edition: StoredEdition
    let upgrade: UpgradeUseCases
    let appStore: FakeAppStore
    let menuItem: BenefitsMenuItem
    let model: BenefitsScreenModel

    init(_ appStore: FakeAppStore) throws {
        let dispatcher = EventDispatcher()
        edition = try StoredEdition(store: SQLiteEditionStore(db: .inMemory()))
        upgrade = UpgradeUseCases(store: edition, appStore: appStore, dispatcher: dispatcher)
        self.appStore = appStore
        menuItem = BenefitsMenuItem(edition: edition)
        menuItem.subscribe(to: dispatcher)
        model = BenefitsScreenModel(commands: upgrade, edition: edition)
    }
}

@MainActor
@Suite struct BenefitsScreenTests {
    @Test func showsTheLocalisedPriceFromTheAppStore() async throws {
        let screen = try Screen(FakeAppStore(price: "2,99 €"))
        #expect(screen.model.price == nil)
        await screen.model.loadPrice()
        #expect(screen.model.price == "2,99 €")

        let offline = try Screen(FakeAppStore(reachable: false))
        await offline.model.loadPrice()
        #expect(offline.model.price == nil)
    }

    @Test func buyingUnlocksAndClosesTheScreen() async throws {
        let screen = try Screen(FakeAppStore(purchaseOutcome: .purchased))
        #expect(screen.model.phase == .ready)
        await screen.model.buy()
        #expect(screen.model.phase == .unlocked)
        #expect(screen.edition.isUnlocked)
        #expect(!screen.menuItem.isVisible)
    }

    @Test func aPendingPurchaseWaitsUntilTheApprovalArrives() async throws {
        let screen = try Screen(FakeAppStore(purchaseOutcome: .pending))
        await screen.model.buy()
        #expect(screen.model.phase == .waitingForApproval)
        #expect(screen.edition.isFree)

        screen.appStore.approvePending()
        screen.appStore.finishUpdates()
        await screen.upgrade.listenForTransactionUpdates()
        screen.model.editionChanged(isFree: screen.menuItem.isVisible)
        #expect(screen.model.phase == .unlocked)
    }

    @Test(arguments: [PurchaseOutcome.cancelled, .failed])
    func cancelAndFailureLeaveTheScreenUnchanged(_ outcome: PurchaseOutcome) async throws {
        let screen = try Screen(FakeAppStore(purchaseOutcome: outcome))
        await screen.model.loadPrice()
        await screen.model.buy()
        #expect(screen.model.phase == .ready)
        #expect(screen.model.message == nil)
        #expect(screen.model.price == "£2.99")
        #expect(screen.edition.isFree)
        #expect(screen.menuItem.isVisible)
    }

    @Test func restoreUnlocksWhenThePurchaseIsOnRecord() async throws {
        let screen = try Screen(FakeAppStore(unlockOnRecord: true))
        await screen.model.restore()
        #expect(screen.model.phase == .unlocked)
        #expect(screen.edition.isUnlocked)
    }

    @Test func restoreWithNothingOnRecordSaysSo() async throws {
        let screen = try Screen(FakeAppStore(unlockOnRecord: false))
        await screen.model.restore()
        #expect(screen.model.phase == .ready)
        #expect(screen.model.message == "Nothing to restore")
        #expect(screen.edition.isFree)
    }

    @Test func restoreOfflineSaysTheAppStoreCouldNotBeReached() async throws {
        let screen = try Screen(FakeAppStore(unlockOnRecord: true, reachable: false))
        await screen.model.restore()
        #expect(screen.model.phase == .ready)
        #expect(screen.model.message == "Couldn't reach the App Store")
        #expect(screen.edition.isFree)
    }

    // MARK: The benefits list (must match the spec's Free limits)

    @Test func listsEveryPaidFeatureOnce() {
        let covered = UpgradeBenefit.all.flatMap(\.features)
        #expect(covered.count == PaidFeature.allCases.count)
        #expect(Set(covered) == Set(PaidFeature.allCases))
    }

    @Test func statesTheFreeLimitsInPlainLanguage() {
        let free = UpgradeBenefit.all.compactMap(\.freeAllows)
        #expect(free == [
            "Free: 1 live match",
            "Free: most frames wins only",
            "Free: alternate breaks only",
            "Free: 5 active players (Me included, archived not counted)",
            "Free: newest 10 ended matches shown",
        ])
        let titles = UpgradeBenefit.all.map(\.title)
        for paidOnly in ["Player colours", "Templates", "Pause by hand", "Head-to-head", "Stats", "Series", "Lock screen scores"] {
            #expect(titles.contains(paidOnly))
        }
        #expect(UpgradeBenefit.freeNote.contains("Auto-pause"))
        #expect(UpgradeBenefit.freeNote.contains("ever deleted"))
    }

    // MARK: The offer router (S52)

    @Test func theRouterOffersInPlaceForTemplatesAndPauseAndTheScreenOtherwise() {
        let edition = FixedEdition.free
        let router = UpgradeOfferRouter(edition: edition)
        #expect(router.request == nil)
        router.show(.templates)
        #expect(router.request?.placement == .inPlace)
        router.show(.manualPause)
        #expect(router.request?.placement == .inPlace)
        router.show(.headToHead)
        #expect(router.request?.placement == .genericScreen)

        edition.status = .unlocked
        router.show(.stats)
        #expect(router.request == nil)
    }
}
