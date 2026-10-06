import Foundation

/// Open-host replay of Matches' published language (ADR-0003). A subscriber that joined late (Stats
/// on a device that recorded matches before Stats existed) or lost its store catches up from here,
/// stream by stream, instead of reading Matches' store. Only Stage 2 events come back, in exactly
/// the shape `MatchEventPublished` was (or would have been) dispatched in.
public protocol MatchEventHistory: Sendable {
    /// Every match stream and its current version (Stage 1 events included in the count).
    func streamVersions() throws -> [UUID: Int]
    /// The published events of one match with a stream version greater than `version`, in order.
    func publishedEvents(of match: UUID, after version: Int) throws -> [MatchEventPublished]
}
