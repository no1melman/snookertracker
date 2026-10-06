import Foundation
import MatchesDomain
import MatchesPublished

/// Matches' open-host queries for Players (`PlayerMatchQueries`, ADR-0002, ADR-0008), answered from
/// the match repository. A failed read fails safe: the archive and merge guards refuse, and the
/// removal asks first.
@MainActor
public final class MatchesForPlayers: PlayerMatchQueries {
    private let repository: any MatchRepository

    public init(repository: any MatchRepository) {
        self.repository = repository
    }

    /// Over the same repository the match use cases write to.
    public convenience init(matches: MatchUseCases) {
        self.init(repository: matches.repository)
    }

    public func isPlayerInLiveMatch(_ player: UUID) -> Bool {
        guard let live = try? repository.findLive() else { return true }
        return live.contains { $0.setup.players.contains(PlayerId(ref: player)) }
    }

    /// Any match between them that still exists (cancelled included): merging would leave a player
    /// against themselves.
    public func havePlayedEachOther(_ a: UUID, _ b: UUID) -> Bool {
        guard let matches = try? repository.findByPlayer(a) else { return true }
        return matches.contains { $0.status != .deleted && $0.setup.players.contains(PlayerId(ref: b)) }
    }

    public func matchCount(of player: UUID) -> Int {
        guard let matches = try? repository.findByPlayer(player) else { return 1 }
        return matches.count { $0.status != .deleted }
    }
}
