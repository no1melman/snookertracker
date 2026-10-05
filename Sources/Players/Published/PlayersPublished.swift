import EventDispatch
import Foundation

/// A Stage 2 player event, Players' published language: dispatched in-process after the player is
/// saved. `type` is a stable name (e.g. "PlayerRenamed"); `payload` is versioned JSON.
public struct PlayerEventPublished: PublishedEvent, Hashable {
    public static let eventType = "Players.PlayerEvent"
    public static let version = 1

    public let playerId: UUID
    public let type: String
    public let schemaVersion: Int
    public let payload: Data
    public let occurredAt: Date

    public init(playerId: UUID, type: String, schemaVersion: Int, payload: Data, occurredAt: Date) {
        self.playerId = playerId
        self.type = type
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.occurredAt = occurredAt
    }
}
