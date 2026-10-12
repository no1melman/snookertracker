import Foundation
import Testing
import UpgradeDomain

private let t0 = Date(timeIntervalSince1970: 1_000)

@Suite("EditionStatus")
struct EditionStatusTests {
    @Test("free → unlocked and unlocked → free are allowed")
    func allowedTransitions() {
        #expect(EditionStatus.free.canTransition(to: .unlocked))
        #expect(EditionStatus.unlocked.canTransition(to: .free))
    }

    @Test("staying put is not a transition")
    func refusedTransitions() {
        #expect(!EditionStatus.free.canTransition(to: .free))
        #expect(!EditionStatus.unlocked.canTransition(to: .unlocked))
    }
}

@Suite("Edition")
struct EditionTests {
    @Test("a new device is Free")
    func initialIsFree() {
        #expect(Edition.initial.status == .free)
        #expect(Edition.initial.domainEvents.isEmpty)
    }

    @Test("unlock makes it Unlocked and raises AppUnlocked")
    func unlockRaises() {
        let unlocked = Edition.initial.unlock(at: t0)
        #expect(unlocked.status == .unlocked)
        #expect(unlocked.domainEvents == [.unlocked(AppUnlocked(occurredAt: t0))])
    }

    @Test("unlock is idempotent once Unlocked: no event")
    func unlockIdempotent() {
        let unlocked = Edition.reconstitute(status: .unlocked)
        #expect(unlocked.unlock(at: t0) == unlocked)
        #expect(unlocked.unlock(at: t0).domainEvents.isEmpty)
    }

    @Test("lock returns it to Free and raises AppLocked")
    func lockRaises() {
        let locked = Edition.reconstitute(status: .unlocked).lock(at: t0)
        #expect(locked.status == .free)
        #expect(locked.domainEvents == [.locked(AppLocked(occurredAt: t0))])
    }

    @Test("lock is idempotent while Free: no event")
    func lockIdempotent() {
        #expect(Edition.initial.lock(at: t0) == Edition.initial)
        #expect(Edition.initial.lock(at: t0).domainEvents.isEmpty)
    }

    @Test("reconstitute raises nothing; clearing drops raised events")
    func reconstituteAndClear() {
        #expect(Edition.reconstitute(status: .unlocked).domainEvents.isEmpty)
        let cleared = Edition.initial.unlock(at: t0).clearingDomainEvents()
        #expect(cleared.domainEvents.isEmpty)
        #expect(cleared.status == .unlocked)
    }

    @Test("Free allows no paid feature", arguments: PaidFeature.allCases)
    func freeAllowsNone(feature: PaidFeature) {
        #expect(!Edition.initial.allows(feature))
    }

    @Test("Unlocked allows every paid feature", arguments: PaidFeature.allCases)
    func unlockedAllowsAll(feature: PaidFeature) {
        #expect(Edition.reconstitute(status: .unlocked).allows(feature))
    }

    @Test("limits are the Free limits while Free and nil once Unlocked")
    func limits() {
        #expect(Edition.initial.limits == .standard)
        #expect(Edition.reconstitute(status: .unlocked).limits == nil)
    }
}

@Suite("FreeLimits and PaidFeature")
struct FreeLimitsTests {
    @Test("the Free limits table")
    func values() {
        let limits = FreeLimits.standard
        #expect(limits.liveMatches == 1)
        #expect(limits.activePlayers == 5)
        #expect(limits.visibleEndedMatches == 10)
        #expect(limits.allowedStyles == [.mostFramesWins])
        #expect(limits.allowedBreakRules == [.alternate])
        #expect(limits.allowsOnlyMostFramesWins)
        #expect(limits.allowsOnlyAlternateBreaks)
    }

    @Test("styles and break rules outside the table are refused")
    func stylesAndBreakRules() {
        let limits = FreeLimits.standard
        #expect(limits.allows(MatchStyleKind.mostFramesWins))
        #expect(!limits.allows(MatchStyleKind.raceTo))
        #expect(!limits.allows(MatchStyleKind.sets))
        #expect(limits.allows(BreakRuleKind.alternate))
        #expect(!limits.allows(BreakRuleKind.winnerBreaks))
    }

    @Test("the counts allow up to the limit, not past it")
    func counts() {
        let limits = FreeLimits.standard
        #expect(limits.allowsAnotherLiveMatch(liveCount: 0))
        #expect(!limits.allowsAnotherLiveMatch(liveCount: 1))
        #expect(limits.allowsAnotherActivePlayer(activeCount: 4))
        #expect(!limits.allowsAnotherActivePlayer(activeCount: 5))
    }

    @Test("the paid features")
    func paidFeatures() {
        #expect(Set(PaidFeature.allCases) == [
            .templates, .manualPause, .raceTo, .sets, .winnerBreaks, .extraPlayers, .fullHistory,
            .colours, .headToHead, .stats, .series, .severalLiveMatches, .lockScreen,
        ])
    }

    @Test("the offer is in place for templates and pause, the generic screen otherwise")
    func offerPlacement() {
        for feature in PaidFeature.allCases {
            let inPlace = feature == .templates || feature == .manualPause
            #expect(feature.offerPlacement == (inPlace ? .inPlace : .genericScreen))
        }
    }

    @Test("the unlock product id refuses a blank identifier")
    func productId() {
        #expect(UnlockProductId("  ") == nil)
        #expect(UnlockProductId(" com.example.unlock ")?.value == "com.example.unlock")
    }
}
