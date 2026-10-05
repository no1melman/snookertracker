import Foundation
import Testing
import MatchesDomain

private let callum = Fixture.callum
private let asher = Fixture.asher
private let t = Fixture.time

@Suite("Match: starting and choosing the breaker")
struct MatchStartTests {
    @Test func startingAMatchAwaitsTheBreakerAtZeroZeroWithTimersRunning() {
        let m = Fixture.newMatch()
        #expect(m.status == .awaitingBreaker)
        #expect(m.score == .zero)
        #expect(m.startTime.date == Fixture.t0)
        #expect(m.currentFrameStartedAt == Fixture.t0)
        #expect(m.matchLength(at: t(5)) == .minutes(5))
        #expect(m.frameLength(at: t(5)) == .minutes(5))
        #expect(m.nextBreaker == nil)
        #expect(m.sides == [Side(player: callum, colour: Fixture.red), Side(player: asher, colour: Fixture.blue)])
        guard case .matchStarted(let e) = m.uncommittedEvents.single else { Issue.record("expected MatchStarted"); return }
        #expect(e.setup == Fixture.setup())
        #expect(e.at == Fixture.t0)
        #expect(e.matchId == Fixture.matchId)
    }

    @Test func aSetsMatchStartsWithASetsScore() {
        let m = Fixture.newMatch(style: .sets(sets: Fixture.target(2), frames: Fixture.target(3)))
        #expect(m.score.description == "(0) 0 – 0 (0)")
    }

    @Test func choosingTheBreakerPutsTheMatchInPlay() {
        let m = Fixture.newMatch().chooseBreaker(asher, at: t(1)).value!
        #expect(m.status == .inPlay)
        #expect(m.nextBreaker?.player == asher)
        #expect(m.uncommittedEvents.last == .breakerChosen(.init(player: asher, at: t(1))))
    }

    @Test func nothingButChoosingTheBreakerOrPausingIsAllowedBeforeABreaker() {
        let m = Fixture.newMatch()
        #expect(m.awardFrame(to: callum, at: t(1)).error == .notAllowed(.awardFrame, status: .awaitingBreaker))
        #expect(m.removeFrame(from: callum, at: t(1)).error == .notAllowed(.removeFrame, status: .awaitingBreaker))
        #expect(m.correctBreaker(callum, at: t(1)).error == .notAllowed(.correctBreaker, status: .awaitingBreaker))
        #expect(m.resume(at: t(1)).error == .notAllowed(.resume, status: .awaitingBreaker))
    }

    @Test func theBreakerCannotBeChosenWhilePausedOrTwice() {
        let paused = Fixture.newMatch().pause(at: t(1)).value!
        #expect(paused.chooseBreaker(callum, at: t(2)).error == .notAllowed(.chooseBreaker, status: .paused))
        #expect(Fixture.inPlay().chooseBreaker(asher, at: t(2)).error == .notAllowed(.chooseBreaker, status: .inPlay))
    }

    @Test func onlyAPlayerInTheMatchCanBreak() {
        #expect(Fixture.newMatch().chooseBreaker(Fixture.stranger, at: t(1)).error == .playerNotInMatch(Fixture.stranger))
    }
}

@Suite("Match: awarding and removing frames")
struct MatchFrameTests {
    @Test func awardingAFrameRecordsItAndRestartsTheFrameTimer() {
        let m = Fixture.inPlay().awardFrame(to: asher, at: t(12)).value!
        #expect(m.score == Score(firstFrames: 0, secondFrames: 1))
        #expect(m.currentFrameStartedAt == t(12))
        #expect(m.frameLength(at: t(15)) == .minutes(3))
        #expect(m.uncommittedEvents.last == .frameWon(.init(
            player: asher, frameNumber: 1, setNumber: 1, length: .minutes(12), breaker: callum, at: t(12))))
        let frame = m.frames.single!
        #expect(frame.winner.player == asher)
        #expect(frame.number == 1)
        #expect(frame.breaker?.player == callum)
        #expect(frame.length == .minutes(12))
        #expect(frame.wonAt == t(12))
    }

    @Test func frameLengthLeavesOutPausedTime() {
        let m = Fixture.inPlay()
            .awardFrame(to: callum, at: t(10)).value!
            .pause(at: t(14)).value!
            .resume(at: t(20)).value!
            .awardFrame(to: asher, at: t(25)).value!
        #expect(m.frames.last?.length == .minutes(9))  // 15 elapsed − 6 paused
        #expect(m.matchLength(at: t(25)) == .minutes(19))
    }

    @Test func frameAndMatchTimersStopWhilePaused() {
        let m = Fixture.inPlay().pause(at: t(10)).value!
        #expect(m.frameLength(at: t(30)) == .minutes(10))
        #expect(m.matchLength(at: t(30)) == .minutes(10))
    }

    @Test func scoringIsRefusedWhilePaused() {
        let m = Fixture.inPlay().awarding([callum]).pause(at: t(5)).value!
        #expect(m.awardFrame(to: callum, at: t(6)).error == .notAllowed(.awardFrame, status: .paused))
        #expect(m.removeFrame(from: callum, at: t(6)).error == .notAllowed(.removeFrame, status: .paused))
    }

    @Test func aFrameCanOnlyGoToAPlayerInTheMatch() {
        #expect(Fixture.inPlay().awardFrame(to: Fixture.stranger, at: t(1)).error == .playerNotInMatch(Fixture.stranger))
        #expect(Fixture.inPlay().removeFrame(from: Fixture.stranger, at: t(1)).error == .playerNotInMatch(Fixture.stranger))
    }

    @Test func removingAFrameTakesThatPlayersMostRecentFrame() {
        let m = Fixture.inPlay().awarding([callum, callum, asher]).removeFrame(from: callum, at: t(10)).value!
        #expect(m.score == Score(firstFrames: 1, secondFrames: 1))
        #expect(m.frames.map(\.winner.player) == [callum, asher])
        #expect(m.frames.map(\.number) == [1, 2])
        #expect(m.uncommittedEvents.last == .frameRemoved(.init(
            player: callum, frameNumber: 2, setNumber: 1, revertedSetWin: nil, at: t(10))))
    }

    @Test func aPlayerOnNothingHasNoFrameToRemove() {
        let m = Fixture.inPlay().awarding([callum])
        #expect(m.removeFrame(from: asher, at: t(5)).error == .noFrameToRemove(asher))
    }

    @Test func removingAFrameLeavesTheTimersAlone() {
        let before = Fixture.inPlay().awarding([callum, asher])  // last + at minute 2
        let after = before.removeFrame(from: asher, at: t(9)).value!
        #expect(after.currentFrameStartedAt == before.currentFrameStartedAt)
        #expect(after.frameLength(at: t(10)) == before.frameLength(at: t(10)))
        #expect(after.matchLength(at: t(10)) == before.matchLength(at: t(10)))
        #expect(after.startTime == before.startTime)
    }
}

@Suite("Match: targets and sets")
struct MatchTargetTests {
    @Test func reachingARaceToTargetAsksForConfirmation() {
        let m = Fixture.inPlay(style: .raceTo(Fixture.target(2))).awarding([callum, asher, callum])
        #expect(m.status == .awaitingConfirmation)
        #expect(m.uncommittedEvents.last == .matchTargetReached(.init(
            player: callum, score: Score(firstFrames: 2, secondFrames: 1), at: t(3))))
    }

    @Test func noFurtherFramesWhileAwaitingConfirmation() {
        let m = Fixture.inPlay(style: .raceTo(Fixture.target(1))).awarding([asher])
        #expect(m.awardFrame(to: callum, at: t(5)).error == .notAllowed(.awardFrame, status: .awaitingConfirmation))
        #expect(m.pause(at: t(5)).error == .notAllowed(.pause, status: .awaitingConfirmation))
    }

    @Test func undoingTheWinningFrameReturnsToPlay() {
        let m = Fixture.inPlay(style: .raceTo(Fixture.target(2))).awarding([callum, callum])
            .removeFrame(from: callum, at: t(5)).value!
        #expect(m.status == .inPlay)
        #expect(m.score == Score(firstFrames: 1, secondFrames: 0))
    }

    @Test func removingTheLosersFrameKeepsTheWinnerOnTargetAwaitingConfirmation() {
        let m = Fixture.inPlay(style: .raceTo(Fixture.target(2))).awarding([asher, callum, callum])
            .removeFrame(from: asher, at: t(5)).value!
        #expect(m.status == .awaitingConfirmation)
        #expect(m.score == Score(firstFrames: 2, secondFrames: 0))
    }

    @Test func mostFramesWinsNeverReachesATarget() {
        let m = Fixture.inPlay().awarding(Array(repeating: callum, count: 20))
        #expect(m.status == .inPlay)
    }

    static let setsStyle = MatchStyle.sets(sets: Fixture.target(2), frames: Fixture.target(2))

    @Test func winningASetRaisesSetWonAndResetsTheCurrentSetFrames() {
        let m = Fixture.inPlay(style: Self.setsStyle).awarding([callum, asher, callum])
        #expect(m.uncommittedEvents.suffix(2) == [
            .frameWon(.init(player: callum, frameNumber: 3, setNumber: 1, length: .minutes(1), breaker: callum, at: t(3))),
            .setWon(.init(player: callum, setNumber: 1, setScore: SetFrames(first: 2, second: 1), at: t(3))),
        ])
        #expect(m.score.description == "(1) 0 – 0 (0)")
        #expect(m.status == .inPlay)
        let next = m.awarding([asher], startMinute: 4)
        #expect(next.frames.last?.setNumber == 2)
        #expect(next.score.description == "(1) 0 – 1 (0)")
    }

    @Test func removingTheSetWinningFrameRevertsTheSetWin() {
        let won = Fixture.inPlay(style: Self.setsStyle).awarding([callum, asher, callum])
        let reverted = won.removeFrame(from: callum, at: t(9)).value!
        #expect(reverted.score.description == "(0) 1 – 1 (0)")
        #expect(reverted.uncommittedEvents.last == .frameRemoved(.init(
            player: callum, frameNumber: 3, setNumber: 1, revertedSetWin: 1, at: t(9))))
    }

    @Test func winningTheDecidingSetReachesTheMatchTarget() {
        let m = Fixture.inPlay(style: Self.setsStyle).awarding([callum, callum, asher, callum, callum])
        guard case .setWon(let set) = m.uncommittedEvents.dropLast().last else { Issue.record("expected SetWon"); return }
        #expect(set.setNumber == 2)
        guard case .matchTargetReached(let reached) = m.uncommittedEvents.last else { Issue.record("expected target"); return }
        #expect(reached.player == callum)
        #expect(reached.score.sets?.firstSets == 2)
        #expect(m.status == .awaitingConfirmation)

        let undone = m.removeFrame(from: callum, at: t(9)).value!
        #expect(undone.status == .inPlay)
        #expect(undone.score.description == "(1) 1 – 1 (0)")
    }
}

@Suite("Match: breaker derivation")
struct MatchBreakerTests {
    private func breakers(_ m: Match) -> [PlayerId?] { m.frames.map { $0.breaker?.player } }

    @Test func alternateBreaksGiveTheFirstBreakerTheOddFrames() {
        let m = Fixture.inPlay().awarding([callum, callum, asher, callum])
        #expect(breakers(m) == [callum, asher, callum, asher])
        #expect(m.nextBreaker?.player == callum)
    }

    @Test func winnerBreaksGivesTheBreakToTheLastWinner() {
        let m = Fixture.inPlay(breakRule: .winnerBreaks).awarding([asher, asher, callum])
        #expect(breakers(m) == [callum, asher, asher])
        #expect(m.nextBreaker?.player == callum)
    }

    @Test func alternateBreakMovesBackAfterRemovingAFrame() {
        let m = Fixture.inPlay().awarding([callum, asher])
        #expect(m.nextBreaker?.player == callum)
        #expect(m.removeFrame(from: asher, at: t(5)).value!.nextBreaker?.player == asher)
    }

    @Test func winnerBreaksFollowsTheLastRemainingFrameAfterRemoval() {
        let m = Fixture.inPlay(breakRule: .winnerBreaks).awarding([asher, callum])
        #expect(m.removeFrame(from: callum, at: t(5)).value!.nextBreaker?.player == asher)
        #expect(m.removeFrame(from: asher, at: t(5)).value!.nextBreaker?.player == callum)
        let empty = Fixture.inPlay(breakRule: .winnerBreaks).awarding([asher]).removeFrame(from: asher, at: t(5)).value!
        #expect(empty.nextBreaker?.player == callum)  // no frames left: the origin
    }

    @Test func correctingTheBreakerRestartsAlternationFromThem() {
        let m = Fixture.inPlay().awarding([callum, asher])  // callum would break frame 3
            .correctBreaker(asher, at: t(5)).value!
        #expect(m.nextBreaker?.player == asher)
        #expect(m.uncommittedEvents.last == .breakerCorrected(.init(player: asher, frameNumber: 3, at: t(5))))
        let later = m.awarding([callum, callum], startMinute: 6)
        #expect(breakers(later).suffix(2) == [asher, callum])
        #expect(later.nextBreaker?.player == asher)
    }

    @Test func correctingTheBreakerOverridesTheLastWinnerUnderWinnerBreaks() {
        let m = Fixture.inPlay(breakRule: .winnerBreaks).awarding([asher])
            .correctBreaker(callum, at: t(5)).value!
        #expect(m.nextBreaker?.player == callum)
        #expect(m.awarding([asher], startMinute: 6).nextBreaker?.player == asher)
    }

    @Test func setsDoNotAffectTheBreak() {
        let style = MatchStyle.sets(sets: Fixture.target(3), frames: Fixture.target(2))
        let m = Fixture.inPlay(style: style).awarding([callum, callum, asher])  // set 1 after frame 2
        #expect(breakers(m) == [callum, asher, callum])
        #expect(m.frames.map(\.setNumber) == [1, 1, 2])
        #expect(m.nextBreaker?.player == asher)
    }

    @Test func theBreakerCanBeCorrectedWhilePausedButNotBeforeOneIsChosen() {
        let paused = Fixture.inPlay().pause(at: t(1)).value!
        #expect(paused.correctBreaker(asher, at: t(2)).value?.nextBreaker?.player == asher)
        let pausedEarly = Fixture.newMatch().pause(at: t(1)).value!
        #expect(pausedEarly.correctBreaker(asher, at: t(2)).error == .noBreakerToCorrect)
    }

    @Test func theBreakerCannotBeCorrectedWhileAwaitingConfirmation() {
        let m = Fixture.inPlay(style: .raceTo(Fixture.target(1))).awarding([callum])
        #expect(m.correctBreaker(asher, at: t(5)).error == .notAllowed(.correctBreaker, status: .awaitingConfirmation))
    }
}

@Suite("Match: pausing and resuming")
struct MatchPauseTests {
    @Test func aMatchCanBePausedAwaitingTheBreakerOrInPlay() {
        let early = Fixture.newMatch().pause(at: t(1)).value!
        #expect(early.status == .paused)
        #expect(early.uncommittedEvents.last == .matchPaused(.init(at: t(1))))
        #expect(Fixture.inPlay().pause(at: t(1)).value?.status == .paused)
    }

    @Test func aPausedMatchCannotBePausedAgain() {
        let paused = Fixture.inPlay().pause(at: t(1)).value!
        #expect(paused.pause(at: t(2)).error == .notAllowed(.pause, status: .paused))
        #expect(paused.autoPause(at: t(2)).error == .notAllowed(.autoPause, status: .paused))
    }

    @Test func resumingReturnsToPlayOrToAwaitingTheBreaker() {
        let inPlay = Fixture.inPlay().pause(at: t(1)).value!.resume(at: t(3)).value!
        #expect(inPlay.status == .inPlay)
        #expect(inPlay.uncommittedEvents.last == .matchResumed(.init(at: t(3))))
        #expect(inPlay.pauses.single?.endedAt == t(3))
        let early = Fixture.newMatch().pause(at: t(1)).value!.resume(at: t(3)).value!
        #expect(early.status == .awaitingBreaker)
    }

    @Test func whilePausedOnlyResumeAndCorrectBreakerOfTheLiveActionsAreAllowed() {
        let paused = Fixture.inPlay().awarding([callum]).pause(at: t(5)).value!
        #expect(paused.overrideColour(of: callum, to: Fixture.green, at: t(6)).error == .notAllowed(.overrideColour, status: .paused))
        #expect(paused.chooseBreaker(callum, at: t(6)).error == .notAllowed(.chooseBreaker, status: .paused))
        #expect(paused.correctBreaker(asher, at: t(6)).value != nil)
        #expect(paused.resume(at: t(6)).value != nil)
    }

    @Test func autoPauseIsStampedWithTheSuppliedTimeEvenIfEarlierThanNow() {
        let m = Fixture.inPlay().awarding([callum])  // last action minute 1
        let paused = m.autoPause(at: t(1)).value!
        #expect(paused.status == .paused)
        #expect(paused.uncommittedEvents.last == .matchAutoPaused(.init(at: t(1))))
        #expect(paused.pauses.single?.isAutomatic == true)
    }

    @Test func autoPauseRefusesATimeBeforeTheLastAction() {
        let m = Fixture.inPlay().awarding([callum, asher])  // last action minute 2
        #expect(m.autoPause(at: t(1.5)).error == .pauseBeforeLastAction(pauseAt: t(1.5), lastActionAt: t(2)))
    }

    @Test func autoPauseIsAllowedAwaitingTheBreakerButNotAwaitingConfirmation() {
        #expect(Fixture.newMatch().autoPause(at: t(1)).value?.status == .paused)
        let confirming = Fixture.inPlay(style: .raceTo(Fixture.target(1))).awarding([callum])
        #expect(confirming.autoPause(at: t(5)).error == .notAllowed(.autoPause, status: .awaitingConfirmation))
    }
}

@Suite("Match: temporary colour")
struct MatchColourTests {
    @Test func bothSidesSharingAColourCanGiveOneSideATemporaryColour() {
        let m = Fixture.newMatch(colours: (Fixture.red, Fixture.red)).overrideColour(of: asher, to: Fixture.green, at: t(0)).value!
        #expect(m.side(of: asher)?.colour == Fixture.green)
        #expect(m.side(of: callum)?.colour == Fixture.red)
        #expect(m.uncommittedEvents.last == .matchColourOverridden(.init(player: asher, colour: Fixture.green, at: t(0))))
    }

    @Test func noTemporaryColourWhenColoursAlreadyDiffer() {
        #expect(Fixture.newMatch().overrideColour(of: asher, to: Fixture.green, at: t(0)).error == .coloursAlreadyDiffer)
    }

    @Test func theTemporaryColourMustBeDifferent() {
        let m = Fixture.newMatch(colours: (Fixture.red, Fixture.red))
        #expect(m.overrideColour(of: asher, to: Fixture.red, at: t(0)).error == .overrideColourNotDifferent(Fixture.red))
    }

    @Test func theTemporaryColourIsOnlyOfferedBeforeTheBreak() {
        let m = Fixture.newMatch(colours: (Fixture.red, Fixture.red)).chooseBreaker(callum, at: t(0)).value!
        #expect(m.overrideColour(of: asher, to: Fixture.green, at: t(1)).error == .notAllowed(.overrideColour, status: .inPlay))
    }

    @Test func framesCarryTheOverriddenColour() {
        let m = Fixture.newMatch(colours: (Fixture.red, Fixture.red))
            .overrideColour(of: asher, to: Fixture.green, at: t(0)).value!
            .chooseBreaker(callum, at: t(0)).value!
            .awarding([asher])
        #expect(m.frames.single?.winner == Side(player: asher, colour: Fixture.green))
    }
}

@Suite("Match: event sourcing")
struct MatchRehydrationTests {
    private func playedMatch() -> Match {
        Fixture.newMatch(style: .sets(sets: Fixture.target(2), frames: Fixture.target(2)), colours: (Fixture.red, Fixture.red))
            .overrideColour(of: asher, to: Fixture.green, at: t(0)).value!
            .chooseBreaker(callum, at: t(0)).value!
            .awarding([callum, asher, callum])
            .pause(at: t(4)).value!
            .correctBreaker(asher, at: t(5)).value!
            .resume(at: t(6)).value!
            .awarding([asher], startMinute: 7)
            .removeFrame(from: callum, at: t(8)).value!
            .autoPause(at: t(9)).value!
    }

    @Test func aMatchRebuildsFromItsEventsToTheSameState() {
        let live = playedMatch()
        let rebuilt = Match.rehydrate(live.uncommittedEvents).value!
        #expect(rebuilt == live.committed())
        #expect(rebuilt.version == live.uncommittedEvents.count)
        #expect(rebuilt.uncommittedEvents.isEmpty)
    }

    @Test func behavioursAfterRehydrationOnlyAddNewEvents() {
        let rebuilt = Match.rehydrate(playedMatch().uncommittedEvents).value!
        let resumed = rebuilt.resume(at: t(30)).value!
        #expect(resumed.uncommittedEvents == [.matchResumed(.init(at: t(30)))])
        #expect(resumed.version == rebuilt.version)
        #expect(resumed.committed().version == rebuilt.version + 1)
    }

    @Test func eventsSurviveEncodingAndRebuildTheSameMatch() throws {
        let live = playedMatch()
        let data = try JSONEncoder().encode(live.uncommittedEvents)
        let decoded = try JSONDecoder().decode([MatchEvent].self, from: data)
        #expect(decoded == live.uncommittedEvents)
        #expect(Match.rehydrate(decoded).value == live.committed())
    }

    @Test func aHistoryMustBeginWithTheMatchStarting() {
        #expect(Match.rehydrate([]).error == .empty)
        #expect(Match.rehydrate([.matchPaused(.init(at: t(1)))]).error == .doesNotBeginWithMatchStarted)
    }

    @Test func lastActionTracksTheLatestEvent() {
        #expect(playedMatch().lastActionAt == t(9))
    }
}

extension Collection {
    var single: Element? { count == 1 ? first : nil }
}
