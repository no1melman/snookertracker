import Foundation
import Testing
import MatchesDomain

private let callum = Fixture.callum
private let asher = Fixture.asher
private let cal = PlayerId.create("cal").value!  // the kept record a folded-in player moves to
private let t = Fixture.time
private let raceTo3 = MatchStyle.raceTo(Fixture.target(3))

@Suite("Match: moving a merged player (S33)")
struct MatchPlayerMovedTests {
    /// Race to 3, Callum wins 3–1 against Asher, finished at minute 10.
    private func finished() -> Match {
        Fixture.inPlay(style: raceTo3).awarding([callum, asher, callum, callum]).finish(at: t(10)).value!
    }

    @Test func movingRepointsTheSetupSidesFramesBreakerAndResult() {
        let moved = finished().movePlayer(from: asher, to: cal, at: t(60)).value!
        #expect(moved.setup.first == callum && moved.setup.second == cal)
        #expect(moved.second == Side(player: cal, colour: Fixture.blue))
        #expect(moved.first == Side(player: callum, colour: Fixture.red))
        #expect(moved.frames.map(\.winner.player) == [callum, cal, callum, callum])
        #expect(moved.frames.compactMap(\.breaker?.player) == [callum, cal, callum, cal])
        #expect(moved.result == .win(Side(player: callum, colour: Fixture.red)))
        #expect(moved.score == Score(firstFrames: 3, secondFrames: 1))
        #expect(moved.status == .finished)
        #expect(moved.uncommittedEvents.last == .matchPlayerMoved(MatchPlayerMoved(from: asher, to: cal, at: t(60))))
    }

    @Test func theWinnerMovesWhenTheFoldedInPlayerWon() {
        let moved = finished().movePlayer(from: callum, to: cal, at: t(60)).value!
        #expect(moved.result == .win(Side(player: cal, colour: Fixture.red)))
        #expect(moved.breakerOrigin?.player == cal)
    }

    @Test func aLiveMatchCarriesOnWithTheKeptPlayer() {
        let live = Fixture.inPlay(style: raceTo3).awarding([asher])
        let moved = live.movePlayer(from: asher, to: cal, at: t(5)).value!
        #expect(moved.status == .inPlay)
        #expect(moved.lastActionAt == live.lastActionAt)  // a correction, not play
        #expect(moved.nextBreaker?.player == cal)
        #expect(moved.awardFrame(to: asher, at: t(6)).error == .playerNotInMatch(asher))
        let next = moved.awardFrame(to: cal, at: t(6)).value!
        #expect(next.score == Score(firstFrames: 0, secondFrames: 2))
    }

    @Test func allowedInEveryStatusButDeleted() {
        let awaiting = Fixture.newMatch()
        let paused = awaiting.pause(at: t(1)).value!
        let abandoned = Fixture.inPlay().abandon(at: t(2)).value!
        let cancelled = Fixture.inPlay().cancel(at: t(2)).value!
        for match in [awaiting, paused, Fixture.inPlay(), finished(), abandoned, cancelled] {
            #expect(match.movePlayer(from: asher, to: cal, at: t(60)).value?.status == match.status)
        }
        let deleted = cancelled.delete(at: t(3)).value!
        #expect(deleted.movePlayer(from: asher, to: cal, at: t(60)).error == .notAllowed(.movePlayer, status: .deleted))
    }

    @Test func refusedWhenTheKeptPlayerIsAlreadyInTheMatch() {
        #expect(finished().movePlayer(from: asher, to: callum, at: t(60)).error == .notAllowed(.movePlayer, status: .finished))
        #expect(finished().movePlayer(from: asher, to: asher, at: t(60)).error == .notAllowed(.movePlayer, status: .finished))
    }

    @Test func refusedWhenTheFoldedInPlayerIsNotInTheMatch() {
        #expect(finished().movePlayer(from: Fixture.stranger, to: cal, at: t(60)).error == .playerNotInMatch(Fixture.stranger))
    }

    @Test func rehydratingTheStreamRebuildsTheMovedMatch() {
        let moved = finished().movePlayer(from: asher, to: cal, at: t(60)).value!
            .correctScore(ScoreCorrection.frames(first: 1, second: 3, for: raceTo3).value!, at: t(70)).value!
        #expect(moved.result == .win(Side(player: cal, colour: Fixture.blue)))
        #expect(Match.rehydrate(moved.uncommittedEvents).value == moved.committed())
    }
}
