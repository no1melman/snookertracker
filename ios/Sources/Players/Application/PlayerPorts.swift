import Foundation

// Ports for the Players context (spec 011, 012). Implementations are @MainActor @Observable.

public typealias PlayerID = UUID

/// `PlayersList` row.
public struct PlayerListItem: Identifiable, Hashable, Sendable {
    public let id: PlayerID
    public var name: String
    /// Palette key (DesignSystem `PlayerColour` raw value).
    public var colour: String
    public var isArchived: Bool

    public init(id: PlayerID, name: String, colour: String, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.colour = colour
        self.isArchived = isArchived
    }
}

/// `PlayersList` + `MeView`.
@MainActor public protocol PlayersListQuery: AnyObject, Sendable {
    /// All players, active first, then by name.
    var players: [PlayerListItem] { get }
    var me: PlayerListItem? { get }
}

/// AddPlayer, RenamePlayer, ChangePlayerColour, SetMe.
@MainActor public protocol PlayerCommands: AnyObject, Sendable {
    @discardableResult
    func addPlayer(named name: String, colour: String) throws -> PlayerID
    func renamePlayer(_ id: PlayerID, to name: String) throws
    func changePlayerColour(_ id: PlayerID, to colour: String) throws
    func setMe(_ id: PlayerID) throws
}

public enum PlayerCommandError: LocalizedError, Equatable {
    case emptyName
    case nameTaken(String)
    /// The name belongs to an archived player; removing them frees it.
    case nameHeldByArchivedPlayer(String)
    case unknownPlayer
    case notAllowedNow

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .nameTaken(let name): "There's already a player called \(name)."
        case .nameHeldByArchivedPlayer(let name): "\(name) is an archived player. Unarchive them, or remove them to reuse the name."
        case .unknownPlayer: "That player no longer exists."
        case .notAllowedNow: "That isn't possible right now."
        }
    }
}
