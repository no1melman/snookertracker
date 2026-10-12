import Foundation
import Testing
import MatchesDomain

private let t = Fixture.time

// Invariant (spec 025, ADR-0010): a Paused match knows how it was paused, for the edition guard on
// ResumeMatch. Derived from the events (MatchPaused → by hand, MatchAutoPaused → automatic).
@Suite("Match: how it was paused")
struct PauseKindTests {
    @Test func aMatchPausedByHandKnowsItWasPausedByHand() {
        let m = Fixture.inPlay().pause(at: t(5)).value!
        #expect(m.pauseKind == .byHand)
    }

    @Test func aMatchPausedAutomaticallyKnowsItWasPausedAutomatically() {
        let m = Fixture.inPlay().autoPause(at: t(5)).value!
        #expect(m.pauseKind == .automatic)
    }

    @Test func aMatchThatIsNotPausedHasNoPauseKind() {
        #expect(Fixture.newMatch().pauseKind == nil)
        #expect(Fixture.inPlay().pauseKind == nil)
        let resumed = Fixture.inPlay().pause(at: t(5)).value!.resume(at: t(6)).value!
        #expect(resumed.pauseKind == nil)
    }

    @Test func thePauseKindFollowsTheLatestPause() {
        let m = Fixture.inPlay()
            .autoPause(at: t(5)).value!
            .resume(at: t(6)).value!
            .pause(at: t(7)).value!
        #expect(m.pauseKind == .byHand)
        let again = m.resume(at: t(8)).value!.autoPause(at: t(9)).value!
        #expect(again.pauseKind == .automatic)
    }

    @Test func aMatchPausedBeforeItsBreakerKnowsHowItWasPaused() {
        #expect(Fixture.newMatch().pause(at: t(1)).value!.pauseKind == .byHand)
        #expect(Fixture.newMatch().autoPause(at: t(1)).value!.pauseKind == .automatic)
    }

    @Test func thePauseKindIsRebuiltFromTheStoredEvents() {
        for paused in [Fixture.inPlay().pause(at: t(5)).value!, Fixture.inPlay().autoPause(at: t(5)).value!] {
            let rebuilt = Match.rehydrate(paused.uncommittedEvents).value!
            #expect(rebuilt.pauseKind == paused.pauseKind)
        }
    }
}
