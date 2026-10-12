import EventDispatch
import Foundation
import MatchesApplication
import MatchesInfrastructure
import PlayersApplication
import PlayersInfrastructure
import SQLiteSupport
import StatsApplication
import StatsInfrastructure
import Testing
import UpgradeApplication
import UpgradeInfrastructure
import UpgradePresentation
import UpgradePublished

// Outside-in over one real SQLite file: every context wired as the composition root wires it (minus
// the iOS adapters), with the real `StoredEdition` and a fake App Store. An unlock then revoke round
// trip must delete or rewrite nothing (ADR-0010), and nothing asks for the offer on its own (S52).

/// Players as Matches sees it, as the composition root adapts it.
@MainActor
private final class Directory: MatchPlayerDirectory {
    let players: PlayersService
    init(_ players: PlayersService) { self.players = players }

    var suggestions: [MatchPlayer] { players.players.filter { !$0.isArchived }.map(Self.map) }
    var me: PlayerRef? { players.me?.id }
    func player(_ id: PlayerRef) -> MatchPlayer? { players.players.first { $0.id == id }.map(Self.map) }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer {
        let id = try players.addPlayer(named: name, colour: colour)
        return player(id)!
    }

    private static func map(_ p: PlayerListItem) -> MatchPlayer { MatchPlayer(id: p.id, name: p.name, colour: p.colour) }
}

/// One launch of the app on `db`.
@MainActor
private final class Launch {
    let db: SQLiteDatabase
    let dispatcher = EventDispatcher()
    let appStore: FakeAppStore
    let edition: StoredEdition
    let upgrade: UpgradeUseCases
    let offers: UpgradeOfferRouter
    let menuItem: BenefitsMenuItem
    let players: PlayersService
    let matches: MatchUseCases
    let records: MatchRecordsProjection
    let templateRepository: SQLiteTemplateRepository
    let templates: TemplateUseCases
    let seriesRepository: SQLiteSeriesRepository
    let seriesList: SeriesListProjection
    let series: SeriesUseCases
    private let directory: Directory
    private var policies: [AnyObject] = []

    init(_ db: SQLiteDatabase, appStore: FakeAppStore = FakeAppStore()) throws {
        self.db = db
        self.appStore = appStore
        edition = try StoredEdition(store: SQLiteEditionStore(db: db))
        upgrade = UpgradeUseCases(store: edition, appStore: appStore, dispatcher: dispatcher)
        offers = UpgradeOfferRouter(edition: edition)
        menuItem = BenefitsMenuItem(edition: edition)
        menuItem.subscribe(to: dispatcher)
        let playerRepository = try SQLitePlayerRepository(db: db)
        players = try PlayersService(
            repository: playerRepository, reader: playerRepository, meStore: SQLiteMeSettingStore(db: db),
            dispatcher: dispatcher, edition: edition)
        directory = Directory(players)
        let settings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db), edition: edition)
        let live = LiveMatchesProjection(players: directory)
        let store = try SQLiteMatchEventStore(db: db, originDevice: DeviceIdentity.id(in: db))
        let statsStore = try SQLiteStatsStore(db: db)
        records = try MatchRecordsProjection(store: statsStore, edition: edition)
        records.subscribe(to: dispatcher)
        seriesRepository = try SQLiteSeriesRepository(db: db)
        seriesList = SeriesListProjection(
            reader: seriesRepository, catalog: StatsStoreSetupCatalog(records: statsStore, players: statsStore))
        series = SeriesUseCases(repository: seriesRepository, list: seriesList, edition: edition)
        series.subscribe(to: dispatcher)
        try series.loadSeries()
        try records.seedPlayers(players.players.map {
            StatsPlayer(id: $0.id, name: $0.name, colour: $0.colour, isArchived: $0.isArchived)
        })
        try records.catchUp(from: SQLiteMatchEventHistory(db: db, store: store))
        matches = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store), settings: settings, players: directory,
            readModel: live, dispatcher: dispatcher, edition: edition)
        templateRepository = try SQLiteTemplateRepository(db: db)
        let templateList = TemplateListProjection(reader: templateRepository, players: directory)
        templates = TemplateUseCases(repository: templateRepository, list: templateList, edition: edition)
        templates.subscribe(to: dispatcher)
        try templates.loadTemplates()
        let deleteMatches = DeleteMatchesOnPlayerRemoved(matches: matches)
        let deleteTemplates = DeleteTemplatesOnPlayerRemoved(templates: templates)
        let combineTemplates = CombineTemplatesAfterMerge(templates: templates)
        let movePlayerMatches = MovePlayerMatches(matches: matches)
        let hideArchived = HideArchivedPlayersTemplates(list: templateList)
        for policy in [deleteMatches, deleteTemplates, combineTemplates, movePlayerMatches, hideArchived] as [AnyObject] {
            policies.append(policy)
        }
        deleteMatches.subscribe(to: dispatcher)
        deleteTemplates.subscribe(to: dispatcher)
        combineTemplates.subscribe(to: dispatcher)
        movePlayerMatches.subscribe(to: dispatcher)
        hideArchived.subscribe(to: dispatcher)
        players.matchQueries = MatchesForPlayers(matches: matches)
        try matches.loadLiveMatches()
    }

    /// Row counts of every table: the whole device database.
    func snapshot() throws -> [String: Int] {
        let tables = try db.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).compactMap { $0.string("name") }
        var counts: [String: Int] = [:]
        for table in tables {
            counts[table] = try db.query("SELECT COUNT(*) AS n FROM \"\(table)\"").first?.int("n") ?? 0
        }
        return counts
    }

    /// Every row of every table except the edition's, as text: proves nothing was rewritten either.
    func contents() throws -> [String] {
        let tables = try db.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).compactMap { $0.string("name") }
        var rows: [String] = []
        for table in tables where !table.lowercased().contains("edition") {
            let columns = try db.query("SELECT name FROM pragma_table_info('\(table)')").compactMap { $0.string("name") }
            let row = columns.map { "quote(\"\($0)\")" }.joined(separator: " || '|' || ")
            let dump = try db.query("SELECT \(row) AS r FROM \"\(table)\"")
            rows.append(contentsOf: dump.compactMap { $0.string("r") }.map { "\(table): \($0)" })
        }
        return rows.sorted()
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "upgrade-roundtrip-\(UUID().uuidString).sqlite")
}

@MainActor
@Suite struct UpgradeRoundTripTests {
    @Test func anUnlockThenRevokeRoundTripDeletesNoMatchPlayerTemplateOrSeries() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try Launch(SQLiteDatabase(url: url), appStore: FakeAppStore(purchaseOutcome: .purchased))

        #expect(try await app.upgrade.purchaseUnlock() == .purchased)
        #expect(app.edition.isUnlocked)

        // Unlocked: more players than Free allows, colours, other styles, more ended matches than Free
        // shows, templates (recorded on start) and a series.
        let names = ["Callum", "Asher", "Dev", "Priya", "Sam", "Jo", "Kit"]
        let colours = ["blue", "orange", "green", "purple", "red", "teal", "pink"]
        let ids = try zip(names, colours).map { try app.players.addPlayer(named: $0, colour: $1) }
        try app.players.setMe(ids[0])
        let styles: [MatchStyle] = [.mostFramesWins, .raceTo(2), .bestOf(3)]
        for i in 0..<12 {
            let opponent = ids[1 + i % (ids.count - 1)]
            let id = try app.matches.startMatch(MatchSetup(
                players: [ids[0], opponent], game: .pool, style: styles[i % styles.count],
                breakRule: i.isMultiple(of: 2) ? .alternate : .winnerBreaks))
            try app.matches.chooseBreaker(id, player: ids[0])
            try app.matches.awardFrame(id, to: ids[0])
            try app.matches.finishMatch(id, anyway: true)
        }
        app.seriesList.refresh()
        let seriesID = try app.series.createSeries(
            name: "Fridays", setups: Array(app.seriesList.setupChoices(including: []).prefix(2)))

        let playersBefore = app.players.players.count
        let templatesBefore = try app.templateRepository.templateList().count
        let seriesBefore = app.seriesList.series.count
        let tablesBefore = try app.snapshot()
        let rowsBefore = try app.contents()
        #expect(playersBefore == names.count)
        #expect(templatesBefore > 0)
        #expect(seriesBefore == 1)

        // Revoked: back to Free. Then a relaunch on the same file reads it all again while Free.
        app.appStore.revoke()
        app.appStore.finishUpdates()
        await app.upgrade.listenForTransactionUpdates()
        #expect(app.edition.isFree)
        #expect(try app.snapshot() == tablesBefore)
        #expect(try app.contents() == rowsBefore)

        let relaunched = try Launch(SQLiteDatabase(url: url))
        #expect(relaunched.edition.isFree)
        #expect(relaunched.players.players.count == playersBefore)
        #expect(try relaunched.templateRepository.templateList().count == templatesBefore)
        #expect(relaunched.seriesList.series.map(\.id) == [seriesID])
        #expect(try relaunched.snapshot() == tablesBefore)
        #expect(try relaunched.contents() == rowsBefore)

        // Unlocking again shows everything that was there.
        relaunched.appStore.unlockOnRecord = true
        #expect(try await relaunched.upgrade.restorePurchases() == .unlocked)
        #expect(try relaunched.contents() == rowsBefore)
    }

    @Test func theOfferIsNeverRequestedOnLaunchOrByAnEditionChange() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try Launch(SQLiteDatabase(url: url), appStore: FakeAppStore(purchaseOutcome: .purchased))
        #expect(app.edition.isFree)
        #expect(app.offers.request == nil)

        // An unlock and a revocation change the menu item, never the offer.
        try await app.upgrade.purchaseUnlock()
        #expect(app.offers.request == nil)
        app.appStore.revoke()
        app.appStore.finishUpdates()
        await app.upgrade.listenForTransactionUpdates()
        #expect(app.edition.isFree)
        #expect(app.menuItem.isVisible)
        #expect(app.offers.request == nil)

        // A relaunch while Free: still nothing until a paid feature is touched.
        let relaunched = try Launch(SQLiteDatabase(url: url))
        #expect(relaunched.offers.request == nil)
        relaunched.offers.show(.stats)
        #expect(relaunched.offers.request?.placement == .genericScreen)
        relaunched.offers.dismiss()
        #expect(relaunched.offers.request == nil)
    }
}
