import Foundation

// Ports for the Players context (spec 011, 012). Implementations are @MainActor @Observable.

public typealias PlayerID = UUID

/// `PlayersList` row.
public struct PlayerListItem: Identifiable, Hashable, Sendable {
    public let id: PlayerID
    public var name: String
    /// The stored palette key (DesignSystem `PlayerColour` raw value), kept whatever the edition: the
    /// composition root supplies it to Matches (recorded at match start) and Stats, which hide colours
    /// on their own while Free (ADR-0011). Players' own screens show `shownColour`.
    public var colour: String
    /// The colour as `PlayersList` and `PlayerSuggestions` show it: omitted (nil) while Free (S22), the
    /// stored `colour` once Unlocked.
    public var shownColour: String?
    public var isArchived: Bool

    public init(id: PlayerID, name: String, colour: String, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.colour = colour
        self.shownColour = colour
        self.isArchived = isArchived
    }

    /// This row with its shown colour omitted unless `shown`.
    public func showingColour(_ shown: Bool) -> PlayerListItem {
        var row = self
        row.shownColour = shown ? colour : nil
        return row
    }
}

/// `PlayersList`, `PlayerSuggestions` + `MeView`.
@MainActor public protocol PlayersListQuery: AnyObject, Sendable {
    /// All players, active first, then by name; `shownColour` omitted while Free.
    var players: [PlayerListItem] { get }
    var me: PlayerListItem? { get }
    /// `PlayerSuggestions(prefix)`: active players whose name starts with `prefix`, case-insensitively.
    /// A blank prefix suggests every active player. `shownColour` omitted while Free.
    func suggestions(prefix: String) -> [PlayerListItem]
    /// Matches (any status but deleted) the player is in: removing asks first when > 0 (ADR-0008).
    func matchCount(of player: PlayerID) -> Int
}

/// AddPlayer, RenamePlayer, ChangePlayerColour, MergePlayers, ArchivePlayer, UnarchivePlayer,
/// RemovePlayer, SetMe.
@MainActor public protocol PlayerCommands: AnyObject, Sendable {
    @discardableResult
    func addPlayer(named name: String, colour: String) throws -> PlayerID
    func renamePlayer(_ id: PlayerID, to name: String) throws
    func changePlayerColour(_ id: PlayerID, to colour: String) throws
    /// Folds `foldedIn` into `kept`; refused when they have played each other.
    func mergePlayers(keep kept: PlayerID, foldIn foldedIn: PlayerID) throws
    /// Refused while the player is in a live match. No confirmation: unarchive reverses it.
    func archivePlayer(_ id: PlayerID) throws
    func unarchivePlayer(_ id: PlayerID) throws
    /// Archived players only. The caller confirms first when `matchCount(of:)` > 0.
    func removePlayer(_ id: PlayerID) throws
    func setMe(_ id: PlayerID) throws
}

public enum PlayerCommandError: LocalizedError, Equatable {
    case emptyName
    case nameTaken(String)
    /// The name belongs to an archived player; removing them (`archived`) frees it.
    case nameHeldByArchivedPlayer(String, archived: PlayerID)
    /// Archive refused: the player is in a live match.
    case inLiveMatch(String)
    /// Merge refused: the two have played each other.
    case havePlayedEachOther(String, String)
    case cannotMergeIntoSelf
    case unknownPlayer
    case notAllowedNow

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .nameTaken(let name): "There's already a player called \(name)."
        case .nameHeldByArchivedPlayer(let name, _): "\(name) is an archived player. Unarchive them, or remove them to reuse the name."
        case .inLiveMatch(let name): "\(name) is in a live match. Finish or abandon it before archiving them."
        case .havePlayedEachOther(let a, let b): "\(a) and \(b) have played each other, so they can't be the same person."
        case .cannotMergeIntoSelf: "Pick a different player to merge into."
        case .unknownPlayer: "That player no longer exists."
        case .notAllowedNow: "That isn't possible right now."
        }
    }
}
