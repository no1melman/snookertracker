import Testing
import MatchesDomain

@Suite("MatchStatus transitions")
struct MatchStatusTests {
    typealias S = MatchStatus

    static let allowed: [S: Set<S>] = [
        .awaitingBreaker: [.inPlay, .paused, .finished, .abandoned, .cancelled],
        .inPlay: [.inPlay, .awaitingConfirmation, .paused, .finished, .abandoned, .cancelled],
        .awaitingConfirmation: [.inPlay, .finished],
        .paused: [.inPlay, .awaitingBreaker, .finished, .abandoned, .cancelled],
        .abandoned: [.finished, .deleted],
        .finished: [.deleted],
        .cancelled: [.deleted],
        .deleted: [],
    ]

    static let allPairs: [(S, S)] = S.allCases.flatMap { from in S.allCases.map { (from, $0) } }

    @Test(arguments: allPairs)
    func eachTransitionIsAllowedExactlyWhenTheTableSaysSo(from: S, to: S) {
        #expect(from.canTransition(to: to) == Self.allowed[from]!.contains(to))
    }

    @Test func finishedNeverBecomesAbandonedAndCancelledNeverChangesExceptDeletion() {
        #expect(!S.finished.canTransition(to: .abandoned))
        #expect(S.cancelled.allowedTransitions == [.deleted])
    }

    @Test func liveStatusesAreTheFourBeforeAnEnding() {
        #expect(S.allCases.filter(\.isLive) == [.awaitingBreaker, .inPlay, .awaitingConfirmation, .paused])
    }
}
