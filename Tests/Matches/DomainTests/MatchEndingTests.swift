import Foundation
import Testing
import MatchesDomain

private let callum = Fixture.callum
private let asher = Fixture.asher
private let t = Fixture.time
private let callumSide = Side(player: callum, colour: Fixture.red)
private let asherSide = Side(player: asher, colour: Fixture.blue)
private let raceTo2 = MatchStyle.raceTo(Fixture.target(2))
private let sets2x2 = MatchStyle.sets(sets: Fixture.target(2), frames: Fixture.target(2))

private func hours(_ h: Double) -> Date { t(h * 60) }

@Suite("Match: finishing")
struct MatchFinishTests {
    @Test func mostFramesWinsFinishesAnyTimeWithTheLeaderWinning() {
        let m = Fixture.inPlay().awarding([callum, asher, callum]).finish(at: t(10)).value!
        #expect(m.status == .finished)
        #expect(m.result == .win(callumSide))
        #expect(m.endedAt == t(10))
        #expect(m.finalLength == .minutes(10))
        #expect(m.uncommittedEvents.last == .matchFinished(.init(
            result: .win(callumSide), score: Score(firstFrames: 2, secondFrames: 1),
            endedAt: t(10), length: .minutes(10), shortOfTarget: false, at: t(10))))
    }

    @Test func aLevelScoreIsADraw() {
        #expect(Fixture.inPlay().awarding([callum, asher]).finish(at: t(5)).value?.result == .draw)
        #expect(Fixture.newMatch().finish(at: t(1)).value?.result == .draw)
    }

    @Test func aPausedMatchCanBeFinishedAndItsLengthLeavesOutThePause() {
        let m = Fixture.inPlay().awarding([asher]).pause(at: t(4)).value!.finish(at: t(10)).value!
        #expect(m.result == .win(asherSide))
        #expect(m.finalLength == .minutes(4))
    }

    @Test func aFrameInProgressIsDropped() {
        let m = Fixture.inPlay().awarding([asher]).finish(at: t(30)).value!
        #expect(m.frames.count == 1)
        #expect(m.score == Score(firstFrames: 0, secondFrames: 1))
    }

    @Test func fromAwaitingConfirmationTheEndTimeIsTheWinningFramesTime() {
        let m = Fixture.inPlay(style: raceTo2).awarding([callum, asher, callum])
            .finish(at: t(20)).value!
        #expect(m.status == .finished)
        #expect(m.result == .win(callumSide))
        #expect(m.endedAt == t(3))
        #expect(m.finalLength == .minutes(3))
        guard case .matchFinished(let e) = m.uncommittedEvents.last else { Issue.record("expected MatchFinished"); return }
        #expect(e.at == t(20))
        #expect(!e.shortOfTarget)
    }

    @Test func aSetsMatchOnTargetFinishesAtTheWinningFrame() {
        let m = Fixture.inPlay(style: sets2x2).awarding([asher, asher, asher, callum, asher])
            .finish(at: t(30)).value!
        #expect(m.result == .win(asherSide))
        #expect(m.endedAt == t(5))
    }

    @Test(arguments: [raceTo2, sets2x2])
    func shortOfTheTargetFinishingIsRefusedAsWillBeAbandoned(style: MatchStyle) {
        let m = Fixture.inPlay(style: style).awarding([callum])
        #expect(m.finish(at: t(5)).error == .finishShortOfTarget)
        #expect(m.pause(at: t(5)).value!.finish(at: t(6)).error == .finishShortOfTarget)
    }

    @Test func shortOfTheTargetFinishingAnywayLetsWhoeverIsAheadWin() {
        let m = Fixture.inPlay(style: raceTo2).awarding([asher]).finish(at: t(5), anyway: true).value!
        #expect(m.status == .finished)
        #expect(m.result == .win(asherSide))
        #expect(m.endedAt == t(5))
        guard case .matchFinished(let e) = m.uncommittedEvents.last else { Issue.record("expected MatchFinished"); return }
        #expect(e.shortOfTarget)
    }

    @Test func finishingASetsMatchAnywayCountsSetsThenCurrentSetFrames() {
        let setUp = Fixture.inPlay(style: sets2x2).awarding([callum, callum, asher])  // (1) 0 – 1 (0)
        #expect(setUp.finish(at: t(9), anyway: true).value?.result == .win(callumSide))
        let level = setUp.awarding([asher], startMinute: 4)  // (1) 0 – 0 (1)
        #expect(level.finish(at: t(9), anyway: true).value?.result == .draw)
        let ahead = level.awarding([asher], startMinute: 5)  // (1) 0 – 1 (1)
        #expect(ahead.finish(at: t(9), anyway: true).value?.result == .win(asherSide))
    }

    @Test func anEndedMatchCannotBeFinishedAgain() {
        let finished = Fixture.inPlay().finish(at: t(1)).value!
        #expect(finished.finish(at: t(2)).error == .notAllowed(.finish, status: .finished))
        let cancelled = Fixture.inPlay().cancel(at: t(1)).value!
        #expect(cancelled.finish(at: t(2), anyway: true).error == .notAllowed(.finish, status: .cancelled))
    }
}

@Suite("Match: abandoning and cancelling")
struct MatchAbandonCancelTests {
    @Test(arguments: [MatchStatus.awaitingBreaker, .inPlay, .paused])
    func aLiveMatchCanBeAbandoned(from status: MatchStatus) {
        let m = match(in: status).abandon(at: t(10)).value!
        #expect(m.status == .abandoned)
        #expect(m.endedAt == t(10))
        #expect(m.result == nil)
        guard case .matchAbandoned(let e) = m.uncommittedEvents.last else { Issue.record("expected MatchAbandoned"); return }
        #expect(e.endedAt == t(10))
        #expect(e.score == m.score)
    }

    @Test(arguments: [MatchStatus.awaitingBreaker, .inPlay, .paused])
    func aLiveMatchCanBeCancelled(from status: MatchStatus) {
        let m = match(in: status).cancel(at: t(10)).value!
        #expect(m.status == .cancelled)
        #expect(m.endedAt == t(10))
        #expect(m.uncommittedEvents.last == .matchCancelled(.init(at: t(10))))
    }

    @Test func awaitingConfirmationOnlyGoesOnToFinishOrBackToPlay() {
        let m = Fixture.inPlay(style: .raceTo(Fixture.target(1))).awarding([asher])
        #expect(m.abandon(at: t(5)).error == .notAllowed(.abandon, status: .awaitingConfirmation))
        #expect(m.cancel(at: t(5)).error == .notAllowed(.cancel, status: .awaitingConfirmation))
    }

    @Test func finishedNeverBecomesAbandonedOrCancelled() {
        let m = Fixture.inPlay().finish(at: t(1)).value!
        #expect(m.abandon(at: t(2)).error == .notAllowed(.abandon, status: .finished))
        #expect(m.cancel(at: t(2)).error == .notAllowed(.cancel, status: .finished))
    }

    @Test func anAbandonedMatchCannotBeAbandonedOrCancelledAgain() {
        let m = Fixture.inPlay().abandon(at: t(1)).value!
        #expect(m.abandon(at: t(2)).error == .notAllowed(.abandon, status: .abandoned))
        #expect(m.cancel(at: t(2)).error == .notAllowed(.cancel, status: .abandoned))
    }

    private func match(in status: MatchStatus) -> Match {
        switch status {
        case .awaitingBreaker: Fixture.newMatch()
        case .paused: Fixture.inPlay().awarding([callum]).pause(at: t(5)).value!
        default: Fixture.inPlay().awarding([callum])
        }
    }
}

@Suite("Match: stale matches")
struct MatchStaleTests {
    private let capped = CappedLength.from(samePairSameWeekdayAverage: .minutes(150))

    /// Last action: the auto-pause at minute 30.
    private func idle() -> Match {
        Fixture.inPlay().awarding([callum, asher], startMinute: 10).autoPause(at: t(30)).value!
    }

    @Test func aMatchIsStaleFromExactlySixHoursIdle() {
        let m = idle()
        #expect(!m.isStale(at: t(30 + 359)))
        #expect(m.isStale(at: t(30 + 360)))
        #expect(m.flagStale(at: t(30 + 359), suggestedEndTime: t(30), cappedLength: capped).error
            == .notStale(idle: .minutes(359)))

        let flagged = m.flagStale(at: t(30 + 360), suggestedEndTime: t(20), cappedLength: capped).value!
        guard case .staleMatchFlagged(let e) = flagged.uncommittedEvents.last else { Issue.record("expected flag"); return }
        #expect(e.idle == .hours(6))
        #expect(e.ranFor == .minutes(30))
        #expect(e.cappedLength == capped)
        #expect(e.suggestedEndTime.date == t(30))  // kept no earlier than the last action
        #expect(flagged.status == .paused)
    }

    @Test func flaggingIsNotAnActionSoTheMatchStaysStale() {
        let flagged = idle().flagStale(at: hours(7), suggestedEndTime: t(30), cappedLength: capped).value!
        #expect(flagged.lastActionAt == t(30))
        #expect(flagged.isStale(at: hours(7)))
    }

    @Test func onlyALiveMatchIsFlagged() {
        let ended = idle().abandon(at: t(31)).value!
        #expect(!ended.isStale(at: hours(20)))
        #expect(ended.flagStale(at: hours(20), suggestedEndTime: t(31), cappedLength: capped).error
            == .notAllowed(.flagStale, status: .abandoned))
    }

    @Test func theSuggestedEndIsTheLastFrameTimePlusTheWinnersAverageFrameLength() {
        let m = idle()  // frames won at minutes 10 (callum, 10 min) and 11 (asher, 1 min)
        #expect(m.suggestedStaleEndTime(winnerAverageFrameLength: .minutes(15), at: hours(8)) == t(30))
        #expect(m.suggestedStaleEndTime(winnerAverageFrameLength: .minutes(40), at: hours(8)) == t(51))
        #expect(m.suggestedStaleEndTime(winnerAverageFrameLength: .hours(20), at: hours(8)) == hours(8))
        let unpaused = Fixture.inPlay().awarding([callum, asher, asher], startMinute: 10)  // asher: 1 min frames
        #expect(unpaused.suggestedStaleEndTime(winnerAverageFrameLength: nil, at: hours(8)) == t(13))
    }

    @Test func resolvingWithResumeResumesAPausedMatch() {
        let m = idle().resolveStale(.resume, at: hours(7)).value!
        #expect(m.status == .inPlay)
        #expect(m.uncommittedEvents.last == .matchResumed(.init(at: hours(7))))
        #expect(!m.isStale(at: hours(7)))
    }

    @Test func resolvingAnUnpausedMatchWithResumeKeepsItInPlayAndNoLongerStale() {
        let m = Fixture.inPlay().awarding([callum]).resolveStale(.resume, at: hours(7)).value!
        #expect(m.status == .inPlay)
        #expect(!m.isStale(at: hours(7)))
    }

    @Test func resolvingWithAChosenTimeFinishesThenWithTheRealLength() {
        let end = ChosenEndTime.create(t(45), lastAction: t(30), now: hours(7)).value!
        let m = idle().resolveStale(.endAt(end), at: hours(7)).value!
        #expect(m.status == .finished)
        #expect(m.endedAt == t(45))
        #expect(m.finalLength == .minutes(30))  // paused from minute 30
        #expect(m.result == .draw)
    }

    @Test func aChosenTimeOutsideLastActionToNowIsRefused() {
        let tooEarly = ChosenEndTime.create(t(15), lastAction: t(10), now: hours(7)).value!
        #expect(idle().resolveStale(.endAt(tooEarly), at: hours(7)).error
            == .invalidEndTime(.beforeLastAction(chosen: t(15), lastAction: t(30))))
        let tooLate = ChosenEndTime.create(hours(8), lastAction: t(30), now: hours(9)).value!
        #expect(idle().resolveStale(.endAt(tooLate), at: hours(7)).error
            == .invalidEndTime(.afterNow(chosen: hours(8), now: hours(7))))
    }

    @Test func resolvingWithACappedLengthFinishesAtTheLastActionWithTheCappedLength() {
        let m = idle().resolveStale(.endCapped(capped), at: hours(7)).value!
        #expect(m.status == .finished)
        #expect(m.endedAt == t(30))
        #expect(m.finalLength == .minutes(150))
    }

    @Test func onlyAStaleMatchsLengthCanBeCapped() {
        #expect(idle().resolveStale(.endCapped(capped), at: hours(6)).error == .notStale(idle: .minutes(330)))
    }

    @Test func resolvingATargetStyleShortOfTargetStillWarnsItWillBeAbandoned() {
        let m = Fixture.inPlay(style: raceTo2).awarding([asher])
        let end = ChosenEndTime.create(t(5), lastAction: t(1), now: hours(7)).value!
        #expect(m.resolveStale(.endAt(end), at: hours(7)).error == .finishShortOfTarget)
        #expect(m.resolveStale(.endAt(end), at: hours(7), anyway: true).value?.result == .win(asherSide))
    }

    @Test func resolvingWithAbandonOrCancelEndsTheMatch() {
        #expect(idle().resolveStale(.abandon, at: hours(7)).value?.status == .abandoned)
        #expect(idle().resolveStale(.cancel, at: hours(7)).value?.status == .cancelled)
    }

    @Test func anEndedMatchHasNothingToResolve() {
        let ended = idle().finish(at: t(31)).value!
        #expect(ended.resolveStale(.resume, at: hours(20)).error == .notAllowed(.resolveStale, status: .finished))
    }
}

@Suite("Match: long-frame warnings")
struct MatchLongFrameTests {
    @Test func theFirstWarningIsAtThirtyMinutes() {
        let m = Fixture.inPlay()
        #expect(m.nextLongFrameWarning == .minutes(30))
        #expect(m.warnLongFrame(at: t(29)).error == .longFrameThresholdNotReached(next: .minutes(30), elapsed: .minutes(29)))
        let warned = m.warnLongFrame(at: t(30)).value!
        #expect(warned.uncommittedEvents.last == .longFrameWarned(.init(
            frameNumber: 1, threshold: .minutes(30), elapsed: .minutes(30), at: t(30))))
    }

    @Test func thenEveryTenMinutes() {
        let warned = Fixture.inPlay().warnLongFrame(at: t(30)).value!
        #expect(warned.nextLongFrameWarning == .minutes(40))
        #expect(warned.warnLongFrame(at: t(39)).error == .longFrameThresholdNotReached(next: .minutes(40), elapsed: .minutes(39)))
        let again = warned.warnLongFrame(at: t(40)).value!
        #expect(again.nextLongFrameWarning == .minutes(50))
    }

    @Test func aLateWarningSkipsToTheNextThresholdAfterIt() {
        let warned = Fixture.inPlay().warnLongFrame(at: t(55)).value!
        guard case .longFrameWarned(let e) = warned.uncommittedEvents.last else { Issue.record("expected warning"); return }
        #expect(e.threshold == .minutes(30))
        #expect(warned.nextLongFrameWarning == .minutes(60))
    }

    @Test func pausedTimeDoesNotCount() {
        let m = Fixture.inPlay().pause(at: t(10)).value!.resume(at: t(30)).value!
        #expect(m.warnLongFrame(at: t(45)).error == .longFrameThresholdNotReached(next: .minutes(30), elapsed: .minutes(25)))
        #expect(m.warnLongFrame(at: t(50)).value != nil)
    }

    @Test func aNewFrameStartsTheThresholdsAgain() {
        let m = Fixture.inPlay().warnLongFrame(at: t(30)).value!.awardFrame(to: callum, at: t(35)).value!
        #expect(m.nextLongFrameWarning == .minutes(30))
        guard case .longFrameWarned(let e) = m.warnLongFrame(at: t(65)).value?.uncommittedEvents.last else {
            Issue.record("expected warning"); return
        }
        #expect(e.frameNumber == 2)
    }

    @Test func onlyInPlay() {
        #expect(Fixture.newMatch().warnLongFrame(at: t(40)).error == .notAllowed(.warnLongFrame, status: .awaitingBreaker))
        let paused = Fixture.inPlay().pause(at: t(31)).value!
        #expect(paused.warnLongFrame(at: t(40)).error == .notAllowed(.warnLongFrame, status: .paused))
        let ended = Fixture.inPlay().finish(at: t(31)).value!
        #expect(ended.warnLongFrame(at: t(40)).error == .notAllowed(.warnLongFrame, status: .finished))
    }

    @Test func aWarningIsNotAnAction() {
        #expect(Fixture.inPlay().warnLongFrame(at: t(30)).value?.lastActionAt == Fixture.t0)
    }
}
