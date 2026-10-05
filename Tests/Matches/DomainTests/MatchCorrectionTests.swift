import Foundation
import Testing
import MatchesDomain

private let callum = Fixture.callum
private let asher = Fixture.asher
private let t = Fixture.time
private let callumSide = Side(player: callum, colour: Fixture.red)
private let asherSide = Side(player: asher, colour: Fixture.blue)
private let raceTo3 = MatchStyle.raceTo(Fixture.target(3))
private let sets2x3 = MatchStyle.sets(sets: Fixture.target(2), frames: Fixture.target(3))

@Suite("Match: correcting an ended match's score")
struct MatchScoreCorrectionTests {
    /// Race to 3, Callum wins 3–1, finished at minute 4.
    private func finished() -> Match {
        Fixture.inPlay(style: raceTo3).awarding([callum, asher, callum, callum]).finish(at: t(10)).value!
    }

    @Test func aRaceToCorrectionRecalculatesTheWinnerAndAddsUntimedFrames() {
        let m = finished()
        let correction = ScoreCorrection.frames(first: 2, second: 3, for: raceTo3).value!
        let corrected = m.correctScore(correction, at: t(60)).value!
        #expect(corrected.score == Score(firstFrames: 2, secondFrames: 3))
        #expect(corrected.result == .win(asherSide))
        #expect(corrected.status == .finished)
        #expect(corrected.endedAt == t(4))
        #expect(corrected.uncommittedEvents.last == .matchScoreCorrected(.init(
            before: Score(firstFrames: 3, secondFrames: 1), after: Score(firstFrames: 2, secondFrames: 3),
            correction: correction, result: .win(asherSide), at: t(60))))

        // Callum's first two frames and Asher's frame are kept; two untimed frames are added for Asher.
        #expect(corrected.frames.map(\.winner.player) == [callum, asher, callum, asher, asher])
        #expect(corrected.frames.map(\.number) == [1, 2, 3, 4, 5])
        #expect(corrected.frames.prefix(3).map(\.wonAt) == [t(1), t(2), t(3)])
        #expect(corrected.frames.suffix(2).allSatisfy { $0.wonAt == nil && $0.length == nil && $0.breaker == nil })
    }

    @Test func theOriginalEventsAreNeverAlteredCorrectionsAreNewEvents() {
        let m = finished()
        let corrected = m.correctScore(ScoreCorrection.frames(first: 3, second: 0, for: raceTo3).value!, at: t(60)).value!
        #expect(Array(corrected.uncommittedEvents.dropLast()) == m.uncommittedEvents)
        #expect(Match.rehydrate(corrected.uncommittedEvents).value == corrected.committed())
    }

    @Test func aRaceToCorrectionMustPutExactlyOneSideOnThisMatchsTarget() {
        let otherTarget = ScoreCorrection.frames(first: 5, second: 2, for: .raceTo(Fixture.target(5))).value!
        #expect(finished().correctScore(otherTarget, at: t(60)).error
            == .invalidScoreCorrection(.raceToNeedsExactlyOneOnTarget(target: 3, first: 5, second: 2)))
        let wrongStyle = ScoreCorrection.sets([SetFrames(first: 3, second: 0)], for: sets2x3).value!
        #expect(finished().correctScore(wrongStyle, at: t(60)).error == .invalidScoreCorrection(.styleMismatch))
    }

    @Test func aSetsCorrectionIsSavedDespiteWarningsWithPerSetFrames() {
        let m = Fixture.inPlay(style: sets2x3).awarding([callum, callum, callum, asher]).finish(at: t(9), anyway: true).value!
        let correction = ScoreCorrection.sets([SetFrames(first: 3, second: 1), SetFrames(first: 4, second: 5)], for: sets2x3).value!
        #expect(correction.warnings == [.setNotWonOnTarget(setNumber: 2), .setsTargetNotReached])
        let corrected = m.correctScore(correction, at: t(60)).value!
        #expect(corrected.score == Score(firstFrames: 7, secondFrames: 6, sets: .init(
            firstSets: 1, secondSets: 0, firstCurrentSetFrames: 4, secondCurrentSetFrames: 5)))
        #expect(corrected.result == .win(callumSide))
        #expect(corrected.frames.map(\.setNumber) == [1, 1, 1, 1] + Array(repeating: 2, count: 9))
        // Set 1 keeps Callum's three frames and adds Asher's; set 2 keeps Asher's frame and adds the rest.
        #expect(corrected.frames.filter { $0.wonAt != nil }.map(\.number) == [1, 2, 3, 5])
    }

    @Test func anAbandonedMatchCanBeCorrectedAndStaysWithoutAResult() {
        let m = Fixture.inPlay().awarding([callum]).abandon(at: t(5)).value!
        let corrected = m.correctScore(ScoreCorrection.frames(first: 1, second: 4, for: .mostFramesWins).value!, at: t(60)).value!
        #expect(corrected.status == .abandoned)
        #expect(corrected.result == nil)
        #expect(corrected.score == Score(firstFrames: 1, secondFrames: 4))
    }

    @Test func aSecondCorrectionReplacesTheFirst() {
        let once = finished().correctScore(ScoreCorrection.frames(first: 1, second: 3, for: raceTo3).value!, at: t(60)).value!
        let twice = once.correctScore(ScoreCorrection.frames(first: 3, second: 2, for: raceTo3).value!, at: t(61)).value!
        #expect(twice.score == Score(firstFrames: 3, secondFrames: 2))
        #expect(twice.result == .win(callumSide))
        #expect(twice.frames.filter { $0.wonAt == nil }.map(\.winner.player) == [asher, callum, callum])
    }

    @Test func onlyAFinishedOrAbandonedMatchCanBeCorrected() {
        let correction = ScoreCorrection.frames(first: 1, second: 0, for: .mostFramesWins).value!
        #expect(Fixture.inPlay().correctScore(correction, at: t(5)).error == .notAllowed(.correctScore, status: .inPlay))
        let cancelled = Fixture.inPlay().cancel(at: t(1)).value!
        #expect(cancelled.correctScore(correction, at: t(5)).error == .notAllowed(.correctScore, status: .cancelled))
        let deleted = Fixture.inPlay().finish(at: t(1)).value!.delete(at: t(2)).value!
        #expect(deleted.correctScore(correction, at: t(5)).error == .notAllowed(.correctScore, status: .deleted))
    }
}

@Suite("Match: marking an abandoned match finished")
struct MatchMarkFinishedTests {
    @Test func anAbandonedMatchBecomesFinishedWithTheLeaderWinning() {
        let abandoned = Fixture.inPlay(style: raceTo3).awarding([asher, callum, asher]).abandon(at: t(9)).value!
        let m = abandoned.markFinished(at: t(60)).value!
        #expect(m.status == .finished)
        #expect(m.result == .win(asherSide))
        #expect(m.endedAt == t(9))
        #expect(m.uncommittedEvents.last == .matchMarkedFinished(.init(result: .win(asherSide), at: t(60))))
    }

    @Test func aLevelAbandonedMatchBecomesADraw() {
        let m = Fixture.inPlay().awarding([asher, callum]).abandon(at: t(9)).value!.markFinished(at: t(60)).value!
        #expect(m.result == .draw)
    }

    @Test func theWinnerFollowsACorrectionMadeWhileAbandoned() {
        let m = Fixture.inPlay().awarding([asher]).abandon(at: t(9)).value!
            .correctScore(ScoreCorrection.frames(first: 2, second: 1, for: .mostFramesWins).value!, at: t(20)).value!
            .markFinished(at: t(60)).value!
        #expect(m.result == .win(callumSide))
    }

    @Test func onlyAbandonedBecomesFinished() {
        #expect(Fixture.inPlay().markFinished(at: t(5)).error == .notAllowed(.markFinished, status: .inPlay))
        #expect(Fixture.inPlay().finish(at: t(1)).value!.markFinished(at: t(5)).error == .notAllowed(.markFinished, status: .finished))
        #expect(Fixture.inPlay().cancel(at: t(1)).value!.markFinished(at: t(5)).error == .notAllowed(.markFinished, status: .cancelled))
    }
}

@Suite("Match: deleting")
struct MatchDeleteTests {
    @Test(arguments: [MatchStatus.finished, .abandoned, .cancelled])
    func anEndedMatchCanBeDeleted(from status: MatchStatus) {
        let m = ended(status).delete(at: t(60)).value!
        #expect(m.status == .deleted)
        #expect(m.uncommittedEvents.last == .matchDeleted(.init(at: t(60))))
        #expect(m.delete(at: t(61)).error == .notAllowed(.delete, status: .deleted))
    }

    @Test func aLiveMatchCannotBeDeleted() {
        #expect(Fixture.inPlay().delete(at: t(5)).error == .notAllowed(.delete, status: .inPlay))
        #expect(Fixture.newMatch().delete(at: t(5)).error == .notAllowed(.delete, status: .awaitingBreaker))
    }

    @Test func aCancelledMatchNeverChangesExceptByDeletion() {
        let m = ended(.cancelled)
        let correction = ScoreCorrection.frames(first: 1, second: 0, for: .mostFramesWins).value!
        #expect(m.finish(at: t(9), anyway: true).error == .notAllowed(.finish, status: .cancelled))
        #expect(m.abandon(at: t(9)).error == .notAllowed(.abandon, status: .cancelled))
        #expect(m.markFinished(at: t(9)).error == .notAllowed(.markFinished, status: .cancelled))
        #expect(m.correctScore(correction, at: t(9)).error == .notAllowed(.correctScore, status: .cancelled))
        #expect(m.resume(at: t(9)).error == .notAllowed(.resume, status: .cancelled))
        #expect(m.delete(at: t(9)).value?.status == .deleted)
    }

    private func ended(_ status: MatchStatus) -> Match {
        let m = Fixture.inPlay().awarding([callum])
        switch status {
        case .finished: return m.finish(at: t(5)).value!
        case .abandoned: return m.abandon(at: t(5)).value!
        default: return m.cancel(at: t(5)).value!
        }
    }
}

@Suite("Match: ending events")
struct MatchEndingRehydrationTests {
    @Test func anEndedCorrectedMatchRebuildsAndSurvivesEncoding() throws {
        let m = Fixture.inPlay(style: sets2x3).awarding([callum, asher])
            .warnLongFrame(at: t(40)).value!
            .flagStale(at: t(2 + 400), suggestedEndTime: t(10), cappedLength: .from(samePairSameWeekdayAverage: nil)).value!
            .resolveStale(.endCapped(.from(samePairSameWeekdayAverage: nil)), at: t(2 + 401), anyway: true).value!
            .correctScore(ScoreCorrection.sets([SetFrames(first: 3, second: 2)], for: sets2x3).value!, at: t(500)).value!
            .delete(at: t(600)).value!
        let data = try JSONEncoder().encode(m.uncommittedEvents)
        let decoded = try JSONDecoder().decode([MatchEvent].self, from: data)
        #expect(decoded == m.uncommittedEvents)
        let rebuilt = Match.rehydrate(decoded).value!
        #expect(rebuilt == m.committed())
        #expect(rebuilt.status == .deleted)
        #expect(rebuilt.finalLength == .hours(3))
        #expect(rebuilt.endedAt == t(2))
        #expect(rebuilt.result == .win(callumSide))
    }

    @Test func anAbandonedMatchRebuildsAndCanThenBeMarkedFinished() {
        let abandoned = Fixture.inPlay().awarding([asher]).abandon(at: t(5)).value!
        let rebuilt = Match.rehydrate(abandoned.uncommittedEvents).value!
        #expect(rebuilt == abandoned.committed())
        #expect(rebuilt.markFinished(at: t(9)).value?.uncommittedEvents == [.matchMarkedFinished(.init(result: .win(asherSide), at: t(9)))])
    }
}
