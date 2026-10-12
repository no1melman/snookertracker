import EventDispatch
import iOSAdapters
import Foundation
import MatchesApplication
import MatchesInfrastructure
import MatchesPresentation
import MatchesPublished
import PlayersApplication
import PlayersInfrastructure
import PlayersPresentation
import SQLiteSupport
import StatsApplication
import StatsInfrastructure
import StatsPresentation
import StatsPublished
import UpgradeApplication
import UpgradeInfrastructure
import UpgradePresentation
import UpgradePublished
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Composition root: opens the device database, builds the adapters and use cases, and hands their
/// ports to the presentation layer. One container per process (`shared`).
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    /// Upgrade (spec 023): the device's cached edition, the `CurrentEdition` open host every other
    /// context reads, and the purchase / restore / App Store update use cases.
    let edition: StoredEdition
    let upgrade: UpgradeUseCases
    /// S52: where a refused paid feature lands; the offer UI presents `request`.
    let upgradeOffers: UpgradeOfferRouter
    let players: PlayersService
    let matchSettings: MatchSettingsService
    let liveMatches: LiveMatchesProjection
    let matchCommands: MatchUseCases
    let staleMatches: StaleMatchQueue
    /// Long-frame warnings (S37) as scheduled local notifications (spec 019).
    let warnLongFrame: WarnLongFrame
    #if canImport(UserNotifications)
    private let notifications = UserNotificationsScheduler()
    private let banners = ForegroundNotificationBanners()
    #endif
    let templateList: TemplateListProjection
    let templateCommands: TemplateUseCases
    let lifecycle: AppLifecycle
    let matchRecords: MatchRecordsProjection
    let seriesList: SeriesListProjection
    let seriesCommands: SeriesUseCases
    let monthlySummaries: MonthlySummaryProjection
    /// S38: run at launch and on every return to the foreground; each month is issued once.
    let issueSummaries: IssueMonthlySummaries
    private let directory: PlayersForMatches
    /// Matches' reactions to Players' events (spec 011). Held here: their subscriptions are weak.
    private var playerPolicies: [AnyObject] = []
    let dispatcher = EventDispatcher()

    private convenience init() {
        do {
            try self.init(database: SQLiteDatabase(url: Self.databaseURL))
        } catch {
            // Without its store the app would silently lose matches; better to stop loudly.
            fatalError("Could not open the SnookerTracker database: \(error)")
        }
    }

    init(
        database db: SQLiteDatabase, lifecycle: AppLifecycle = AppLifecycle(),
        appStore: any AppStorePort = AppContainer.makeAppStore()
    ) throws {
        self.lifecycle = lifecycle
        // Upgrade first (ADR-0011): it depends on nothing, and every other context reads its edition.
        edition = try StoredEdition(store: SQLiteEditionStore(db: db))
        upgrade = UpgradeUseCases(store: edition, appStore: appStore, dispatcher: dispatcher)
        upgradeOffers = UpgradeOfferRouter(edition: edition)
        let playerRepository = try SQLitePlayerRepository(db: db)
        players = try PlayersService(
            repository: playerRepository, reader: playerRepository, meStore: SQLiteMeSettingStore(db: db),
            dispatcher: dispatcher, edition: edition)
        directory = PlayersForMatches(list: players, commands: players)
        matchSettings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db), edition: edition)
        liveMatches = LiveMatchesProjection(players: directory)
        let store = try SQLiteMatchEventStore(db: db, originDevice: DeviceIdentity.id(in: db))
        // Stats (spec 013): subscribe before any command can dispatch, then catch up on everything
        // Matches published before Stats existed (or since it last ran), via Matches' open host replay.
        let statsStore = try SQLiteStatsStore(db: db)
        matchRecords = try MatchRecordsProjection(store: statsStore, edition: edition)
        matchRecords.subscribe(to: dispatcher)
        // Series (spec 016) lives in Stats: subscribed after the records, so player names are current
        // before the series list refreshes on a merge or removal.
        let seriesRepository = try SQLiteSeriesRepository(db: db)
        seriesList = SeriesListProjection(
            reader: seriesRepository, catalog: StatsStoreSetupCatalog(records: statsStore, players: statsStore))
        seriesCommands = SeriesUseCases(repository: seriesRepository, list: seriesList, edition: edition)
        seriesCommands.subscribe(to: dispatcher)
        try seriesCommands.loadSeries()
        monthlySummaries = MonthlySummaryProjection(
            stats: matchRecords, series: seriesRepository, me: { [players] in players.me?.id })
        issueSummaries = IssueMonthlySummaries(
            repository: seriesRepository, summaries: monthlySummaries,
            log: try SQLiteSeriesSummaryLog(db: db), dispatcher: dispatcher)
        try matchRecords.seedPlayers(players.players.map {
            StatsPlayer(id: $0.id, name: $0.name, colour: $0.colour, isArchived: $0.isArchived)
        })
        try matchRecords.catchUp(from: SQLiteMatchEventHistory(db: db, store: store))
        matchCommands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store), settings: matchSettings, players: directory,
            readModel: liveMatches, dispatcher: dispatcher, edition: edition)
        #if canImport(UserNotifications)
        warnLongFrame = WarnLongFrame(matches: liveMatches, scheduler: notifications)
        #else
        warnLongFrame = WarnLongFrame(matches: liveMatches, scheduler: InMemoryNotificationScheduler())
        #endif
        warnLongFrame.subscribe(to: dispatcher)
        staleMatches = StaleMatchQueue(commands: StaleMatchUseCases(
            matches: matchCommands, stats: matchRecords, players: directory))
        // Templates (spec 008): CreateOrUseTemplate reacts to MatchStarted once it is stored.
        let templateRepository = try SQLiteTemplateRepository(db: db)
        templateList = TemplateListProjection(reader: templateRepository, players: directory)
        templateCommands = TemplateUseCases(repository: templateRepository, list: templateList, edition: edition)
        templateCommands.subscribe(to: dispatcher)
        try templateCommands.loadTemplates()
        // Spec 011: Matches reacts to PlayerRemoved / PlayersMerged / PlayerArchived, and answers
        // Players' open-host questions (archive and merge guards, how many matches a removal deletes).
        let deleteMatches = DeleteMatchesOnPlayerRemoved(matches: matchCommands)
        let deleteTemplates = DeleteTemplatesOnPlayerRemoved(templates: templateCommands)
        let combineTemplates = CombineTemplatesAfterMerge(templates: templateCommands)
        let hideArchived = HideArchivedPlayersTemplates(list: templateList)
        let movePlayerMatches = MovePlayerMatches(matches: matchCommands)
        deleteMatches.subscribe(to: dispatcher)
        deleteTemplates.subscribe(to: dispatcher)
        combineTemplates.subscribe(to: dispatcher)
        movePlayerMatches.subscribe(to: dispatcher)
        hideArchived.subscribe(to: dispatcher)
        playerPolicies = [deleteMatches, deleteTemplates, combineTemplates, movePlayerMatches, hideArchived]
        templateList.seedArchived(players.players.filter(\.isArchived).map(\.id))
        players.matchQueries = MatchesForPlayers(matches: matchCommands)
        // S27 before anything reads live matches; then the stale check (S28) once Stats exists.
        try AppLaunchSequence(lifecycle: lifecycle, matches: matchCommands, afterAutoPause: [
            { [staleMatches] in try staleMatches.flag() },
        ]).run(launchedInBackground: AppLifecycle.processLaunchedInBackground)
        try matchCommands.loadLiveMatches()
        warnLongFrame.rescheduleAll()
        askForNotificationsOnFirstMatch()
        deliverSeriesSummaries()
        issueSummaries.run()
        // Verified unlocks (Ask to Buy approvals, even after a restart) and revocations (S49, S51).
        Task { [upgrade] in await upgrade.listenForTransactionUpdates() }
        #if DEBUG
        seedDemoIfRequested()
        #endif
    }

    /// Notification permission is asked when a match starts (after Welcome, when a long-frame
    /// warning makes sense); iOS only shows the prompt once and returns the stored answer after.
    private func askForNotificationsOnFirstMatch() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().delegate = banners
        var asked = false
        dispatcher.subscribe(MatchEventPublished.self) { [notifications, warnLongFrame] event in
            guard event.type == "MatchStarted", !asked else { return }
            asked = true
            Task { @MainActor in
                if await notifications.requestAuthorization() { warnLongFrame.rescheduleAll() }
            }
        }
        #endif
    }

    /// A monthly series summary arrives as a notification on the 1st (spec 019).
    private func deliverSeriesSummaries() {
        #if canImport(UserNotifications)
        dispatcher.subscribe(SeriesSummaryIssuedPublished.self) { [notifications] e in
            notifications.deliver(
                title: e.seriesName, body: e.text, at: e.occurredAt,
                id: "series-summary.\(e.seriesId).\(e.year)-\(e.month)")
        }
        #endif
    }

    /// The App Store seam (ADR-0011's anti-corruption layer): the StoreKit 2 adapter (spec 028);
    /// tests and previews pass `FakeAppStore`. Nothing else in the app knows which one runs.
    nonisolated static func makeAppStore() -> any AppStorePort {
        #if canImport(StoreKit)
        StoreKitAppStore()
        #else
        FakeAppStore(purchaseOutcome: .purchased)
        #endif
    }

    /// Application Support/SnookerTracker/SnookerTracker.sqlite
    static var databaseURL: URL {
        URL.applicationSupportDirectory.appending(path: "SnookerTracker", directoryHint: .isDirectory)
            .appending(path: "SnookerTracker.sqlite")
    }

    /// S52: a refused paid feature routes here.
    var showUpgradeOffer: ShowUpgradeOfferAction {
        { [upgradeOffers] feature in upgradeOffers.show(feature) }
    }

    var upgradePorts: UpgradePorts { UpgradePorts(edition: edition, commands: upgrade) }

    var playersPorts: PlayersPorts {
        PlayersPorts(list: players, commands: players, edition: edition, showUpgradeOffer: showUpgradeOffer)
    }

    var matchesPorts: MatchesPorts {
        MatchesPorts(live: liveMatches, screens: liveMatches, commands: matchCommands, settings: matchSettings,
                     players: directory, templates: templateList, templateCommands: templateCommands,
                     headToHead: LiveHeadToHead.lookup(matchRecords),
                     edition: edition, showUpgradeOffer: showUpgradeOffer)
    }

    var seriesPorts: SeriesPorts {
        SeriesPorts(
            list: seriesList, commands: seriesCommands, summaries: monthlySummaries,
            edition: edition, showUpgradeOffer: showUpgradeOffer)
    }

    /// History match detail: Edit score, Mark finished, Delete (spec 015).
    var matchDetailActions: MatchDetailActions {
        MatchDetailActions(
            correctScore: { [matchCommands] id, edit, confirmed in
                let score: CorrectedScore = switch edit {
                case .frames(let p): .frames(first: p.first, second: p.second)
                case .sets(let sets): .sets(sets.map { SetScore(first: $0.first, second: $0.second) })
                }
                do {
                    try matchCommands.correctMatchScore(id, to: score, confirmed: confirmed)
                    return []
                } catch MatchCommandError.correctionNeedsConfirmation(let warnings) {
                    return warnings
                }
            },
            markFinished: { [matchCommands] in try matchCommands.markMatchFinished($0) },
            delete: { [matchCommands] in try matchCommands.deleteMatch($0) })
    }

    /// New Game's swipe to archive (ADR-0008), adapted from Players.
    var archivePlayer: ArchivePlayerAction {
        { [players] id in try players.archivePlayer(id) }
    }

    var statsPorts: StatsPorts {
        StatsPorts(
            history: matchRecords, deleteMatch: { [matchCommands] in try matchCommands.deleteMatch($0) },
            stats: matchRecords, me: { [players] in players.me?.id },
            edition: edition, showUpgradeOffer: showUpgradeOffer)
    }
}

/// Customer/supplier adapter: Players as Matches sees it (`MatchPlayerDirectory`).
@MainActor
final class PlayersForMatches: MatchPlayerDirectory {
    private let list: any PlayersListQuery
    private let commands: any PlayerCommands

    init(list: any PlayersListQuery, commands: any PlayerCommands) {
        self.list = list
        self.commands = commands
    }

    var suggestions: [MatchPlayer] { list.players.filter { !$0.isArchived }.map(Self.map) }
    var me: PlayerRef? { list.me?.id }

    func player(_ id: PlayerRef) -> MatchPlayer? { list.players.first { $0.id == id }.map(Self.map) }

    func addPlayer(named name: String, colour: String) throws -> MatchPlayer {
        let id = try commands.addPlayer(named: name, colour: colour)
        guard let player = player(id) else { throw PlayerCommandError.unknownPlayer }
        return player
    }

    private static func map(_ p: PlayerListItem) -> MatchPlayer { MatchPlayer(id: p.id, name: p.name, colour: p.colour) }
}

#if DEBUG
extension AppContainer {
    /// Screenshot aid only: `-uiDemo` seeds two players and a live match. Only seeds when no Me exists yet, so it persists like any other data.
    func seedDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-uiDemo"), players.me == nil else { return }
        guard let me = try? players.addPlayer(named: "Callum", colour: "blue"),
              let asher = try? players.addPlayer(named: "Asher", colour: "orange") else { return }
        guard let dev = try? players.addPlayer(named: "Dev", colour: "green") else { return }
        try? players.setMe(me)
        let matches = matchCommands
        guard let m = try? matches.startMatch(MatchSetup(players: [asher, me], game: .pool, style: .raceTo(5), breakRule: .alternate)) else { return }
        try? matches.chooseBreaker(m, player: asher)
        for p in [asher, me, asher, asher, me, me, asher] { try? matches.awardFrame(m, to: p) }
        if let m2 = try? matches.startMatch(MatchSetup(players: [me, dev], game: .snooker, style: .bestOf(7), breakRule: .winnerBreaks)) {
            try? matches.chooseBreaker(m2, player: me)
            try? matches.awardFrame(m2, to: me)
            try? matches.pauseMatch(m2)
        }
        // Earlier, cancelled starts, so New Game has templates with different use counts (spec 008).
        for setup in [
            MatchSetup(players: [asher, me], game: .pool, style: .raceTo(5), breakRule: .alternate),
            MatchSetup(players: [asher, me], game: .pool, style: .raceTo(5), breakRule: .alternate),
            MatchSetup(players: [dev, asher], game: .pool, style: .mostFramesWins, breakRule: .alternate),
        ] {
            if let id = try? matches.startMatch(setup) { try? matches.cancelMatch(id) }
        }
        seedHistoryDemo(me: me, asher: asher, dev: dev)
    }

    /// `-uiRoute live|newGame|players|settings|history|match` opens that screen at launch.
    var demoRoute: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiRoute"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
