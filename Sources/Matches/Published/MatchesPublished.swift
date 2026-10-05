import EventDispatch
import Foundation

/// A Stage 2 match event, Matches' published language (ADR-0003): dispatched in-process after the
/// event is stored. `type`, `schemaVersion` and the JSON `payload` are the same versioned contract
/// the event store writes, so subscribers (Stats, Live Activity) decode exactly what was recorded.
public struct MatchEventPublished: PublishedEvent, Hashable {
    public static let eventType = "Matches.MatchEvent"
    public static let version = 1

    public let matchId: UUID
    public let eventId: UUID
    public let originDevice: UUID
    /// 1-based position on the match's stream.
    public let streamVersion: Int
    /// Stable event name, e.g. "FrameWon".
    public let type: String
    public let schemaVersion: Int
    public let payload: Data
    public let occurredAt: Date

    public init(
        matchId: UUID, eventId: UUID, originDevice: UUID, streamVersion: Int,
        type: String, schemaVersion: Int, payload: Data, occurredAt: Date
    ) {
        self.matchId = matchId
        self.eventId = eventId
        self.originDevice = originDevice
        self.streamVersion = streamVersion
        self.type = type
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.occurredAt = occurredAt
    }
}
