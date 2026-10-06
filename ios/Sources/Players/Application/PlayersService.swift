import EventDispatch
import Foundation
import Observation
import PlayersDomain
import PlayersPublished

// MARK: - Persistence ports (spec 011, 012)

/// `PlayerRepository`: state-stored.
public protocol PlayerRepository: Sendable {
    func getById(_ id: PlayerId) throws -> Player?
    func save(_ player: Player) throws
    /// Case-insensitive, including archived players; a name-holding player wins over a freed one.
    func findByName(_ name: PlayerName) throws -> Player?
    /// From the colours of existing (active and archived) players.
    func nextUnusedColour() throws -> Colour
}

/// `PlayersList` read side: a direct query, no aggregates.
public protocol PlayersListReader: Sendable {
    /// Active and archived players, active first, then by name.
    func list() throws -> [PlayerListItem]
}

/// `MeSettingStore`: one per device.
public protocol MeSettingStore: Sendable {
    func get() throws -> MeSetting
    func save(_ setting: MeSetting) throws
}

// MARK: - Use cases + read models

/// AddPlayer, RenamePlayer, ChangePlayerColour, SetMe behind `PlayerCommands`, and the `PlayersList`
/// / `MeView` read models behind `PlayersListQuery`. Each command is load → domain → save → dispatch,
/// then the list is re-read.
@MainActor @Observable
public final class PlayersService: PlayersListQuery, PlayerCommands {
    private let repository: any PlayerRepository
    private let reader: any PlayersListReader
    private let meStore: any MeSettingStore
    private let dispatcher: EventDispatcher
    private let now: @Sendable () -> Date

    public private(set) var players: [PlayerListItem] = []
    private var meSetting: MeSetting = .unset

    public init(
        repository: any PlayerRepository, reader: any PlayersListReader, meStore: any MeSettingStore,
        dispatcher: EventDispatcher, now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.repository = repository
        self.reader = reader
        self.meStore = meStore
        self.dispatcher = dispatcher
        self.now = now
        players = try reader.list()
        meSetting = try meStore.get()
    }

    public var me: PlayerListItem? {
        guard let id = meSetting.me?.value else { return nil }
        return players.first { $0.id == id }
    }

    // MARK: Commands

    public func addPlayer(named name: String, colour: String) throws -> PlayerID {
        let name = try Self.name(name)
        let colour = try Colour(rawValue: colour) ?? repository.nextUnusedColour()
        let id = PlayerId.new()
        let player = try Self.unwrap(
            Player.add(id: id, name: name, colour: colour, sameNamed: try repository.findByName(name), at: now()), name)
        try commit(player)
        return id.value
    }

    public func renamePlayer(_ id: PlayerID, to name: String) throws {
        let name = try Self.name(name)
        let player = try load(id)
        try commit(try Self.unwrap(player.rename(to: name, sameNamed: try repository.findByName(name), at: now()), name))
    }

    public func changePlayerColour(_ id: PlayerID, to colour: String) throws {
        guard let colour = Colour(rawValue: colour) else { throw PlayerCommandError.notAllowedNow }
        let player = try load(id)
        try commit(try Self.unwrap(player.changeColour(to: colour, at: now()), player.name))
    }

    /// `SetMe`: an active (or archived) player only.
    public func setMe(_ id: PlayerID) throws {
        let player = try load(id)
        guard player.status.holdsName else { throw PlayerCommandError.unknownPlayer }
        let next = meSetting.set(player.id)
        try meStore.save(next)
        meSetting = next
    }

    // MARK: Plumbing

    private func load(_ id: PlayerID) throws -> Player {
        guard let player = try repository.getById(PlayerId(id)) else { throw PlayerCommandError.unknownPlayer }
        return player
    }

    /// save → dispatch → refresh the read model.
    private func commit(_ player: Player) throws {
        try repository.save(player)
        dispatcher.dispatch(player.domainEvents.compactMap(PlayerEventWire.published))
        players = try reader.list()
    }

    private static func name(_ raw: String) throws -> PlayerName {
        guard case .success(let name) = PlayerName.create(raw) else { throw PlayerCommandError.emptyName }
        return name
    }

    private static func unwrap(_ result: Result<Player, PlayerError>, _ name: PlayerName) throws -> Player {
        switch result {
        case .success(let player): return player
        case .failure(.nameTaken): throw PlayerCommandError.nameTaken(name.value)
        case .failure(.nameHeldByArchivedPlayer): throw PlayerCommandError.nameHeldByArchivedPlayer(name.value)
        case .failure(.playerNoLongerExists): throw PlayerCommandError.unknownPlayer
        case .failure: throw PlayerCommandError.notAllowedNow
        }
    }
}

/// Player events in Players' published language: stable type names, versioned JSON payloads.
enum PlayerEventWire {
    static func published(_ event: PlayerEvent) -> PlayerEventPublished? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        let encoded: (type: String, id: PlayerId, at: Date, payload: Data)?
        switch event {
        case .added(let e): encoded = try? ("PlayerAdded", e.playerId, e.occurredAt, encoder.encode(e))
        case .renamed(let e): encoded = try? ("PlayerRenamed", e.playerId, e.occurredAt, encoder.encode(e))
        case .colourChanged(let e): encoded = try? ("PlayerColourChanged", e.playerId, e.occurredAt, encoder.encode(e))
        case .merged(let e): encoded = try? ("PlayersMerged", e.foldedInPlayerId, e.occurredAt, encoder.encode(e))
        case .archived(let e): encoded = try? ("PlayerArchived", e.playerId, e.occurredAt, encoder.encode(e))
        case .unarchived(let e): encoded = try? ("PlayerUnarchived", e.playerId, e.occurredAt, encoder.encode(e))
        case .removed(let e): encoded = try? ("PlayerRemoved", e.playerId, e.occurredAt, encoder.encode(e))
        }
        guard let encoded else { return nil }
        return PlayerEventPublished(
            playerId: encoded.id.value, type: encoded.type, schemaVersion: 1, payload: encoded.payload, occurredAt: encoded.at)
    }
}
