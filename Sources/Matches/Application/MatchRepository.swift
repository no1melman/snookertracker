import Foundation
import MatchesDomain

// Persistence ports for the Matches context (spec 006, 007). Adapters live in MatchesInfrastructure.

/// One event as stored on a match's stream.
public struct RecordedMatchEvent: Hashable, Sendable {
    /// Globally unique, so streams from several devices can be merged later.
    public let eventId: UUID
    /// The device that recorded it.
    public let originDevice: UUID
    /// 1-based position in the match's stream.
    public let streamVersion: Int
    public let event: MatchEvent

    public init(eventId: UUID, originDevice: UUID, streamVersion: Int, event: MatchEvent) {
        self.eventId = eventId
        self.originDevice = originDevice
        self.streamVersion = streamVersion
        self.event = event
    }
}

public enum MatchRepositoryError: Error, Equatable, Sendable {
    /// Someone appended to the stream since the match was loaded (optimistic concurrency).
    case concurrencyConflict(match: MatchID, expectedVersion: Int, actualVersion: Int)
    /// The stored history could not be rebuilt into a match.
    case corruptStream(match: MatchID, detail: String)
}

/// `MatchRepository` (spec 006): event-sourced. `save` appends the match's uncommitted events,
/// expecting the stream to still be at `match.version`.
public protocol MatchRepository: Sendable {
    /// The match rebuilt from its stream; nil when there is no such stream.
    func getById(_ id: MatchID) throws -> Match?
    /// Appends `match.uncommittedEvents` atomically; throws `concurrencyConflict` if the stream moved.
    @discardableResult
    func save(_ match: Match) throws -> [RecordedMatchEvent]
    /// Live matches, oldest started first (ties by creation order).
    func findLive() throws -> [Match]
    /// Every match with that player, oldest started first.
    func findByPlayer(_ player: PlayerRef) throws -> [Match]
}

/// What `MatchSettings` holds (spec 007): defaults for new matches and the live-match limit.
public struct MatchSettingsValues: Hashable, Sendable, Codable {
    public var defaults: MatchesDomain.MatchDefaults
    public var liveMatchLimit: LiveMatchLimit

    public init(defaults: MatchesDomain.MatchDefaults, liveMatchLimit: LiveMatchLimit) {
        self.defaults = defaults
        self.liveMatchLimit = liveMatchLimit
    }

    /// pool, most frames wins, alternate; limit 10.
    public static let initial = MatchSettingsValues(defaults: .initial, liveMatchLimit: .standard)
}

/// `MatchSettingsStore` (spec 007): one per device.
public protocol MatchSettingsStore: Sendable {
    /// nil until first saved.
    func get() throws -> MatchSettingsValues?
    func save(_ settings: MatchSettingsValues) throws
}
