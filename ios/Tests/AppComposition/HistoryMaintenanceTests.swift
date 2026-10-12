@testable import AppComposition
import EventDispatch
import Foundation
import MatchesApplication
import MatchesInfrastructure
import SQLiteSupport
import StatsPresentation
import Testing
import UpgradePublished

// The History maintenance adapters (specs 015, 025) over the real Matches use cases and event store
// on in-memory SQLite, with Upgrade's `FixedEdition`: a Free refusal never reports a success.

private let callum = UUID()
private let asher = UUID()

@MainActor
private final class Players: MatchPlayerDirectory {
    let all = [MatchPlayer(id: callum, name: "Callum", colour: "blue"), MatchPlayer(id: asher, name: "Asher", colour: "orange")]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
}

@MainActor
private struct Stack {
    let repository: EventSourcedMatchRepository
    let commands: MatchUseCases
    let clock = Clock()

    init(_ status: EditionStatus) throws {
        let db = try SQLiteDatabase.inMemory()
        let edition = FixedEdition(status)
        repository = EventSourcedMatchRepository(store: try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db)))
        let players = Players()
        let clock = clock
        commands = MatchUseCases(
            repository: repository, settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)),
            players: players, readModel: LiveMatchesProjection(players: players, edition: edition),
            dispatcher: EventDispatcher(), edition: edition, now: { clock.now })
    }

    /// One more ended match (1–0) than Free shows, oldest first.
    func pastTheLimit() throws -> [UUID] {
        try (0...FreeLimits.standard.visibleEndedMatches).map { _ in
            clock.now = clock.now.addingTimeInterval(600)
            let id = try commands.startMatch(MatchSetup(players: [callum, asher], game: .pool, style: .mostFramesWins, breakRule: .alternate))
            try commands.chooseBreaker(id, player: callum)
            try commands.awardFrame(id, to: callum)
            try commands.finishMatch(id)
            return id
        }
    }
}

@MainActor
@Suite("History maintenance adapters")
struct HistoryMaintenanceTests {
    @Test func aRefusedCorrectionIsNotASaveAndDefersTheOffer() throws {
        let stack = try Stack(.free)
        let ended = try stack.pastTheLimit()
        let before = try stack.repository.getById(ended[0])
        let correct = HistoryMaintenance.correctScore(stack.commands)

        #expect(try correct(ended[0], .frames(ScorePair(first: 3, second: 1)), true) == .refused(.fullHistory))
        #expect(try stack.repository.getById(ended[0]) == before)

        #expect(try correct(ended[1], .frames(ScorePair(first: 3, second: 1)), true) == .saved)
        #expect(try stack.repository.getById(ended[1])?.score.firstFrames == 3)
    }

    @Test func unlockedCorrectsAnyEndedMatch() throws {
        let stack = try Stack(.unlocked)
        let ended = try stack.pastTheLimit()
        let correct = HistoryMaintenance.correctScore(stack.commands)
        #expect(try correct(ended[0], .frames(ScorePair(first: 2, second: 0)), true) == .saved)
    }

    @Test func aRefusedDeletionOpensTheOfferAndReportsNothingDeleted() throws {
        let stack = try Stack(.free)
        let ended = try stack.pastTheLimit()
        var offered: [PaidFeature] = []
        let delete = HistoryMaintenance.deleteOrOffer(stack.commands, showUpgradeOffer: { offered.append($0) })

        #expect(try delete(ended[0]) == false)
        #expect(offered == [.fullHistory])
        #expect(try stack.repository.getById(ended[0])?.status == .finished)

        #expect(try delete(ended[1]) == true)
        #expect(offered == [.fullHistory])
    }
}
