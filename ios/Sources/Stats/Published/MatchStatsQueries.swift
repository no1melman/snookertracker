import Foundation

/// Stats' open-host queries for Matches (context map: Stats → Matches, ADR-0003): the live screen's
/// head-to-head (S14) and the stale-match prompt's suggested end time and capped length (S28).
/// Matches depends on this protocol; Stats implements it and the composition root hands it over.
/// Matches never reads Stats' store.
///
/// Player ids are followed through merges, so a merged-away player's matches count for the kept one.
/// Removed players' matches never count.
@MainActor public protocol MatchStatsQueries: AnyObject, Sendable {
    /// `HeadToHead(PlayerId, PlayerId)`: every finished match between the two, in any game and any
    /// style, from `a`'s point of view. Live, abandoned and cancelled matches are not counted, so the
    /// live match itself never is.
    func headToHead(_ a: UUID, _ b: UUID) -> HeadToHead
    /// `AverageFrameTime(PlayerId)`: the average length (minus paused time) of frames the player won
    /// in finished matches; nil when they have none.
    func averageFrameTime(_ player: UUID) -> TimeInterval?
    /// `AverageMatchLength(players, weekday)`: the average length (minus paused time) of finished
    /// matches between the two players that started on `weekday` (`Calendar` weekday: 1 = Sunday …
    /// 7 = Saturday); nil when there are none (Matches then falls back to 3 h).
    func averageMatchLength(_ a: UUID, _ b: UUID, weekday: Int) -> TimeInterval?
}

/// The all-time head-to-head between two players, from the first player's point of view.
public struct HeadToHead: Hashable, Sendable {
    public let won: Int
    public let drawn: Int
    public let lost: Int
    public let framesWon: Int
    public let framesLost: Int
    /// Decider frames won and lost (match deciders included).
    public let decidersWon: Int
    public let decidersLost: Int

    public init(won: Int, drawn: Int, lost: Int, framesWon: Int, framesLost: Int, decidersWon: Int, decidersLost: Int) {
        self.won = won; self.drawn = drawn; self.lost = lost
        self.framesWon = framesWon; self.framesLost = framesLost
        self.decidersWon = decidersWon; self.decidersLost = decidersLost
    }

    public static let none = HeadToHead(won: 0, drawn: 0, lost: 0, framesWon: 0, framesLost: 0, decidersWon: 0, decidersLost: 0)

    public var matches: Int { won + drawn + lost }
    /// No finished match between the two: the live screen hides the section.
    public var isEmpty: Bool { matches == 0 }
    /// Deciders are shown only when there is a value.
    public var showsDeciders: Bool { decidersWon + decidersLost > 0 }
}
