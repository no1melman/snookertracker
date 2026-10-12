import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import SQLiteSupport
import Testing
import UpgradePublished

// Spec 026: the Free limits on Template and MatchSettings, outside-in over the real SQLite stores.
// The edition is Upgrade's `FixedEdition` test double; flipping its status simulates an unlock or a
// revocation. Free starts here stay inside the Free limits (one live match, most frames wins,
// alternate breaks), so they hold whatever `StartMatch` guards.

private typealias Defaults = MatchesApplication.MatchDefaults

private let callum = UUID()
private let asher = UUID()

@MainActor
private final class EditionPlayers: MatchPlayerDirectory {
    let all = [
        MatchPlayer(id: callum, name: "Callum", colour: "blue"),
        MatchPlayer(id: asher, name: "Asher", colour: "orange"),
    ]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

/// Matches, settings and templates sharing one edition, wired as the composition root does.
@MainActor
private struct EditionStack {
    let db: SQLiteDatabase
    let edition: FixedEdition
    let dispatcher = EventDispatcher()
    let settings: MatchSettingsService
    let matches: MatchUseCases
    let templates: TemplateUseCases
    let list: TemplateListProjection

    init(_ status: EditionStatus) throws {
        db = try .inMemory()
        edition = FixedEdition(status)
        let players = EditionPlayers()
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        settings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db), edition: edition)
        settings.subscribe(to: dispatcher)
        matches = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store), settings: settings, players: players,
            readModel: LiveMatchesProjection(players: players), dispatcher: dispatcher, edition: edition)
        let repository = try SQLiteTemplateRepository(db: db)
        list = TemplateListProjection(reader: repository, players: players)
        templates = TemplateUseCases(repository: repository, list: list, edition: edition)
        templates.subscribe(to: dispatcher)
        try templates.loadTemplates()
    }

    /// A match inside the Free limits, finished straight away so the next one may start.
    func playFreeMatch() throws {
        let id = try matches.startMatch(
            MatchSetup(players: [asher, callum], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        try matches.finishMatch(id, anyway: false)
    }

    func storedUseCounts() throws -> [Int] {
        try db.query("SELECT use_count FROM templates ORDER BY rowid").map { $0.int("use_count")! }
    }

    func unlock() {
        edition.status = .unlocked
        dispatcher.dispatch([AppUnlockedPublished(occurredAt: Date())])
    }

    func lock() {
        edition.status = .free
        dispatcher.dispatch([AppLockedPublished(occurredAt: Date())])
    }
}

@Suite("Templates edition guards (integration)") @MainActor
struct TemplatesEditionGuardsTests {
    @Test func templatesRecordedWhileFreeAppearOnUnlock() throws {
        let s = try EditionStack(.free)
        try s.playFreeMatch()
        try s.playFreeMatch()

        // Recorded silently: stored, but the prompt replaces the list.
        #expect(try s.storedUseCounts() == [2])
        #expect(s.list.showsUpgradePrompt)
        #expect(s.list.templates.isEmpty)

        s.unlock()
        #expect(!s.list.showsUpgradePrompt)
        let row = try #require(s.list.templates.first)
        #expect(Set(row.players.map(\.name)) == ["Asher", "Callum"])
        #expect(row.style == .mostFramesWins)
        #expect(row.useCount == 2)
    }

    @Test func freeRefusesDeletionAndShowsThePrompt() throws {
        let s = try EditionStack(.unlocked)
        try s.playFreeMatch()
        let id = try #require(s.list.templates.first).id

        s.lock()
        #expect(s.list.showsUpgradePrompt)
        #expect(s.list.templates.isEmpty)
        #expect(throws: UpgradeRequired(.templates)) { try s.templates.deleteTemplate(id) }
        #expect(PaidFeature.templates.offerPlacement == .inPlace)
        // Nothing deleted or rewritten.
        #expect(try s.storedUseCounts() == [1])

        s.unlock()
        #expect(s.list.templates.map(\.id) == [id])
        try s.templates.deleteTemplate(id)
        #expect(try s.storedUseCounts().isEmpty)
    }

    @Test func theRemovedPlayerCascadeIsNeverLimited() throws {
        let s = try EditionStack(.free)
        try s.playFreeMatch()
        #expect(try s.storedUseCounts() == [1])

        try s.templates.deleteTemplates(of: asher)
        #expect(try s.storedUseCounts().isEmpty)
    }
}

@Suite("Match settings edition guards (integration)") @MainActor
struct MatchSettingsEditionGuardsTests {
    @Test func freeUsesTheFreeLiveMatchLimitWhateverIsStored() throws {
        let s = try EditionStack(.unlocked)
        try s.settings.setLiveMatchLimit(7)

        s.lock()
        let freeLimit = try #require(s.edition.limits).liveMatches
        #expect(s.settings.liveMatchLimit == freeLimit)
        #expect(s.settings.effectiveLiveMatchLimit.value == freeLimit)
        #expect(throws: UpgradeRequired(.severalLiveMatches)) { try s.settings.setLiveMatchLimit(3) }
        s.settings.changeLiveMatchLimit(3)  // the no-error-channel form keeps the old value too
        // The stored limit is untouched, also after a relaunch.
        #expect(s.settings.values.liveMatchLimit.value == 7)
        let relaunched = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: s.db), edition: s.edition)
        #expect(relaunched.values.liveMatchLimit.value == 7)
        #expect(relaunched.liveMatchLimit == freeLimit)

        s.unlock()
        #expect(s.settings.liveMatchLimit == 7)
        try s.settings.setLiveMatchLimit(3)
        #expect(s.settings.liveMatchLimit == 3)
    }

    @Test func freeUsesTheFreeDefaultsAndKeepsTheGameEditable() throws {
        let s = try EditionStack(.unlocked)
        try s.settings.changeDefaults(Defaults(game: .snooker, style: .raceTo(5), breakRule: .winnerBreaks))

        s.lock()
        // The details screen is offered most frames wins and alternate breaks, with the stored game.
        #expect(s.settings.defaults == Defaults(game: .snooker, style: .mostFramesWins, breakRule: .alternate))

        #expect(throws: UpgradeRequired(.raceTo)) {
            try s.settings.changeDefaults(Defaults(game: .snooker, style: .bestOf(7), breakRule: .alternate))
        }
        #expect(throws: UpgradeRequired(.sets)) {
            try s.settings.changeDefaults(Defaults(game: .snooker, style: .sets(sets: 2, frames: 3), breakRule: .alternate))
        }
        #expect(throws: UpgradeRequired(.winnerBreaks)) {
            try s.settings.changeDefaults(Defaults(game: .snooker, style: .mostFramesWins, breakRule: .winnerBreaks))
        }

        // S20: the game stays free; the stored style and break rule are not rewritten.
        try s.settings.changeDefaults(Defaults(game: .pool, style: .mostFramesWins, breakRule: .alternate))
        #expect(s.settings.defaults == Defaults(game: .pool, style: .mostFramesWins, breakRule: .alternate))
        let stored = try #require(try SQLiteMatchSettingsStore(db: s.db).get())
        #expect(stored.defaults == MatchesDomain.MatchDefaults(
            game: .pool, style: .raceTo(try Target.raceTo(5).get()), breakRule: .winnerBreaks))

        s.unlock()
        #expect(s.settings.defaults == Defaults(game: .pool, style: .raceTo(5), breakRule: .winnerBreaks))
    }

    @Test func unlockedChangesEverySettingAsBefore() throws {
        let s = try EditionStack(.unlocked)
        try s.settings.changeDefaults(Defaults(game: .snooker, style: .sets(sets: 2, frames: 3), breakRule: .winnerBreaks))
        try s.settings.setLiveMatchLimit(42)
        #expect(s.settings.defaults == Defaults(game: .snooker, style: .sets(sets: 2, frames: 3), breakRule: .winnerBreaks))
        #expect(s.settings.liveMatchLimit == 42)
    }
}
