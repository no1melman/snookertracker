import EventDispatch
import Foundation
import MatchesPublished
import Observation
import PlayersDomain
import PlayersPublished
import UpgradePublished

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

/// Every Players use case behind `PlayerCommands`, and the `PlayersList` / `PlayerSuggestions` /
/// `MeView` read models behind `PlayersListQuery`. Each command is load → domain → save → Me policies
/// → dispatch, then the list is re-read.
///
/// Archive and merge ask Matches' open host (`PlayerMatchQueries`). Matches is built after Players,
/// so the composition root sets `matchQueries` once it exists; until then those two are refused.
@MainActor @Observable
public final class PlayersService: PlayersListQuery, PlayerCommands {
    private let repository: any PlayerRepository
    private let reader: any PlayersListReader
    private let meStore: any MeSettingStore
    private let dispatcher: EventDispatcher
    private let now: @Sendable () -> Date
    /// Matches' `IsPlayerInLiveMatch`, `HavePlayedEachOther` and match count (ADR-0002, ADR-0008).
    @ObservationIgnored public var matchQueries: (any PlayerMatchQueries)?
    /// Upgrade's `CurrentEdition` open host (ADR-0011): read it before a guarded action. Unlocked
    /// (no limits) until the composition root hands over the device's edition.
    @ObservationIgnored public var edition: any CurrentEdition

    public private(set) var players: [PlayerListItem] = []
    private var meSetting: MeSetting = .unset

    public init(
        repository: any PlayerRepository, reader: any PlayersListReader, meStore: any MeSettingStore,
        dispatcher: EventDispatcher, matchQueries: (any PlayerMatchQueries)? = nil,
        edition: any CurrentEdition = FixedEdition.unlocked,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.repository = repository
        self.reader = reader
        self.meStore = meStore
        self.dispatcher = dispatcher
        self.matchQueries = matchQueries
        self.edition = edition
        self.now = now
        players = try reader.list()
        meSetting = try meStore.get()
    }

    // MARK: Read models

    public var me: PlayerListItem? {
        guard let id = meSetting.me?.value else { return nil }
        return players.first { $0.id == id }
    }

    public func suggestions(prefix: String) -> [PlayerListItem] {
        let key = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return players.filter { !$0.isArchived && $0.name.lowercased().hasPrefix(key) }
    }

    public func matchCount(of player: PlayerID) -> Int {
        matchQueries?.matchCount(of: player) ?? 0
    }

    // MARK: Commands

    /// `AddPlayer`. An archived player's name throws `nameHeldByArchivedPlayer`, carrying that player
    /// so the caller can offer `RemovePlayer`.
    @discardableResult
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

    /// `MergePlayers` (S33): asks Matches `HavePlayedEachOther`. Only the folded-in player changes here;
    /// its matches and templates move via Matches' `PlayersMerged` policies, Me via `UpdateMeOnMerge`.
    public func mergePlayers(keep kept: PlayerID, foldIn foldedIn: PlayerID) throws {
        guard kept != foldedIn else { throw PlayerCommandError.cannotMergeIntoSelf }
        let keptPlayer = try load(kept)
        let folded = try load(foldedIn)
        guard let matchQueries else { throw PlayerCommandError.notAllowedNow }
        let played = matchQueries.havePlayedEachOther(kept, foldedIn)
        try commit(try Self.unwrap(
            folded.mergeInto(keptPlayer, havePlayedEachOther: played, at: now()), folded.name, other: keptPlayer.name))
    }

    /// `ArchivePlayer` (S34): asks Matches `IsPlayerInLiveMatch`.
    public func archivePlayer(_ id: PlayerID) throws {
        let player = try load(id)
        guard let matchQueries else { throw PlayerCommandError.notAllowedNow }
        let live = matchQueries.isPlayerInLiveMatch(id)
        try commit(try Self.unwrap(player.archive(isInLiveMatch: live, at: now()), player.name))
    }

    /// `UnarchivePlayer` (S35).
    public func unarchivePlayer(_ id: PlayerID) throws {
        let player = try load(id)
        try commit(try Self.unwrap(player.unarchive(at: now()), player.name))
    }

    /// `RemovePlayer` (S42): archived only. Confirmation is the UI's (ADR-0008: only when
    /// `matchCount(of:)` > 0). The cascade is Matches' `PlayerRemoved` policies; Me via `ClearMeOnRemoval`.
    public func removePlayer(_ id: PlayerID) throws {
        let player = try load(id)
        try commit(try Self.unwrap(player.remove(at: now()), player.name))
    }

    /// `SetMe`: an active (or archived) player only.
    public func setMe(_ id: PlayerID) throws {
        let player = try load(id)
        guard player.status.holdsName else { throw PlayerCommandError.unknownPlayer }
        try saveMe(meSetting.set(player.id))
    }

    // MARK: Plumbing

    private func load(_ id: PlayerID) throws -> Player {
        guard let player = try repository.getById(PlayerId(id)) else { throw PlayerCommandError.unknownPlayer }
        return player
    }

    /// save → Me policies → dispatch → refresh the read model.
    private func commit(_ player: Player) throws {
        try repository.save(player)
        let me = player.domainEvents.reduce(meSetting, MePolicies.react)
        if me != meSetting { try saveMe(me) }
        dispatcher.dispatch(player.domainEvents.compactMap(PlayerEventWire.published))
        players = try reader.list()
    }

    private func saveMe(_ next: MeSetting) throws {
        try meStore.save(next)
        meSetting = next
    }

    private static func name(_ raw: String) throws -> PlayerName {
        guard case .success(let name) = PlayerName.create(raw) else { throw PlayerCommandError.emptyName }
        return name
    }

    /// Domain refusals as `PlayerCommandError`s that explain themselves. `name` is the subject's (or the
    /// requested) name; `other` the kept player's, for a merge.
    private static func unwrap(
        _ result: Result<Player, PlayerError>, _ name: PlayerName, other: PlayerName? = nil
    ) throws -> Player {
        switch result {
        case .success(let player): return player
        case .failure(.nameTaken): throw PlayerCommandError.nameTaken(name.value)
        case .failure(.nameHeldByArchivedPlayer(let archived)):
            throw PlayerCommandError.nameHeldByArchivedPlayer(name.value, archived: archived.value)
        case .failure(.playerNoLongerExists): throw PlayerCommandError.unknownPlayer
        case .failure(.inLiveMatch): throw PlayerCommandError.inLiveMatch(name.value)
        case .failure(.havePlayedEachOther): throw PlayerCommandError.havePlayedEachOther(other?.value ?? "", name.value)
        case .failure(.cannotMergeIntoSelf): throw PlayerCommandError.cannotMergeIntoSelf
        case .failure(.invalidTransition), .failure(.keptPlayerNotActive): throw PlayerCommandError.notAllowedNow
        }
    }
}

/// `UpdateMeOnMerge` and `ClearMeOnRemoval` (spec 012): Me's reactions to `PlayersMerged` and
/// `PlayerRemoved`. In-context policies, so they run on the domain events right after the save.
enum MePolicies {
    static func react(_ me: MeSetting, to event: PlayerEvent) -> MeSetting {
        switch event {
        case .merged(let e): me.followingMerge(foldedIn: e.foldedInPlayerId, kept: e.keptPlayerId)
        case .removed(let e): me.clearingOnRemoval(of: e.playerId)
        default: me
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
