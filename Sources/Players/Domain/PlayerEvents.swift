import Foundation

public struct PlayerAdded: Hashable, Sendable, Codable {
    public let playerId: PlayerId
    public let name: PlayerName
    public let colour: Colour
    public let occurredAt: Date

    public init(playerId: PlayerId, name: PlayerName, colour: Colour, occurredAt: Date) {
        self.playerId = playerId
        self.name = name
        self.colour = colour
        self.occurredAt = occurredAt
    }
}

public struct PlayerRenamed: Hashable, Sendable, Codable {
    public let playerId: PlayerId
    public let oldName: PlayerName
    public let newName: PlayerName
    public let occurredAt: Date

    public init(playerId: PlayerId, oldName: PlayerName, newName: PlayerName, occurredAt: Date) {
        self.playerId = playerId
        self.oldName = oldName
        self.newName = newName
        self.occurredAt = occurredAt
    }
}

public struct PlayerColourChanged: Hashable, Sendable, Codable {
    public let playerId: PlayerId
    public let oldColour: Colour
    public let newColour: Colour
    public let occurredAt: Date

    public init(playerId: PlayerId, oldColour: Colour, newColour: Colour, occurredAt: Date) {
        self.playerId = playerId
        self.oldColour = oldColour
        self.newColour = newColour
        self.occurredAt = occurredAt
    }
}

public struct PlayersMerged: Hashable, Sendable, Codable {
    public let keptPlayerId: PlayerId
    public let foldedInPlayerId: PlayerId
    public let occurredAt: Date

    public init(keptPlayerId: PlayerId, foldedInPlayerId: PlayerId, occurredAt: Date) {
        self.keptPlayerId = keptPlayerId
        self.foldedInPlayerId = foldedInPlayerId
        self.occurredAt = occurredAt
    }
}

public struct PlayerArchived: Hashable, Sendable, Codable {
    public let playerId: PlayerId
    public let occurredAt: Date

    public init(playerId: PlayerId, occurredAt: Date) {
        self.playerId = playerId
        self.occurredAt = occurredAt
    }
}

public struct PlayerUnarchived: Hashable, Sendable, Codable {
    public let playerId: PlayerId
    public let occurredAt: Date

    public init(playerId: PlayerId, occurredAt: Date) {
        self.playerId = playerId
        self.occurredAt = occurredAt
    }
}

public struct PlayerRemoved: Hashable, Sendable, Codable {
    public let playerId: PlayerId
    public let occurredAt: Date

    public init(playerId: PlayerId, occurredAt: Date) {
        self.playerId = playerId
        self.occurredAt = occurredAt
    }
}

/// Every event the `Player` aggregate raises.
public enum PlayerEvent: Hashable, Sendable, Codable {
    case added(PlayerAdded)
    case renamed(PlayerRenamed)
    case colourChanged(PlayerColourChanged)
    case merged(PlayersMerged)
    case archived(PlayerArchived)
    case unarchived(PlayerUnarchived)
    case removed(PlayerRemoved)
}
