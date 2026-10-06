import Foundation

/// `WhoAmI` (spec 012): which player is Me on this device, displayed "Me (Callum)". Stats reads it
/// as its default point of view (ADR-0003).
public struct WhoAmI: Hashable, Sendable {
    public let id: PlayerID
    public let name: String

    public init(id: PlayerID, name: String) {
        self.id = id
        self.name = name
    }

    /// "Me (Callum)".
    public var displayName: String { "Me (\(name))" }
}

public extension PlayersListQuery {
    /// `WhoAmI`: nil until Me is set (the welcome asks first).
    var whoAmI: WhoAmI? { me.map { WhoAmI(id: $0.id, name: $0.name) } }
}

/// The welcome's name step (S48). Me is set only once the walkthrough is done or skipped, so the
/// full-screen welcome stays up until then.
public enum Welcome {
    /// The player the scorer will be: adds them, or, if the welcome was interrupted after adding them
    /// (or Me was cleared), takes the active player of that name. An archived player's name is still refused.
    @MainActor
    public static func player(
        named name: String, colour: String, list: any PlayersListQuery, commands: any PlayerCommands
    ) throws -> PlayerID {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !key.isEmpty, let existing = list.players.first(where: { !$0.isArchived && $0.name.lowercased() == key }) {
            return existing.id
        }
        return try commands.addPlayer(named: name, colour: colour)
    }
}
