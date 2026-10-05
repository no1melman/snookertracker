import EventDispatch
import Foundation
import MatchesApplication
import MatchesInfrastructure
import MatchesPresentation
import PlayersApplication
import PlayersInfrastructure
import PlayersPresentation
import SQLiteSupport

/// Composition root: opens the device database, builds the adapters and use cases, and hands their
/// ports to the presentation layer. One container per process (`shared`).
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let players: PlayersService
    let matchSettings: MatchSettingsService
    let liveMatches: LiveMatchesProjection
    let matchCommands: MatchUseCases
    private let directory: PlayersForMatches
    private let dispatcher = EventDispatcher()

    private convenience init() {
        do {
            try self.init(database: SQLiteDatabase(url: Self.databaseURL))
        } catch {
            // Without its store the app would silently lose matches; better to stop loudly.
            fatalError("Could not open the SnookerTracker database: \(error)")
        }
    }

    init(database db: SQLiteDatabase) throws {
        let playerRepository = try SQLitePlayerRepository(db: db)
        players = try PlayersService(
            repository: playerRepository, reader: playerRepository, meStore: SQLiteMeSettingStore(db: db),
            dispatcher: dispatcher)
        directory = PlayersForMatches(list: players, commands: players)
        matchSettings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db))
        liveMatches = LiveMatchesProjection(players: directory)
        let store = try SQLiteMatchEventStore(db: db, originDevice: DeviceIdentity.id(in: db))
        matchCommands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store), settings: matchSettings, players: directory,
            readModel: liveMatches, dispatcher: dispatcher)
        try matchCommands.loadLiveMatches()
        #if DEBUG
        seedDemoIfRequested()
        #endif
    }

    /// Application Support/SnookerTracker/SnookerTracker.sqlite
    static var databaseURL: URL {
        URL.applicationSupportDirectory.appending(path: "SnookerTracker", directoryHint: .isDirectory)
            .appending(path: "SnookerTracker.sqlite")
    }

    var playersPorts: PlayersPorts { PlayersPorts(list: players, commands: players) }

    var matchesPorts: MatchesPorts {
        MatchesPorts(live: liveMatches, screens: liveMatches, commands: matchCommands, settings: matchSettings,
                     players: directory)
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
    }

    /// `-uiRoute live|newGame|players|settings` opens that screen at launch.
    var demoRoute: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiRoute"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
