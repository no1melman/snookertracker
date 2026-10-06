import Foundation

/// Matches' open-host queries for Players (context map: Matches → Players, ADR-0002, ADR-0008):
/// the archive guard, the merge guard and the remove confirmation. Players depends on this protocol;
/// Matches implements it and the composition root hands it over.
@MainActor public protocol PlayerMatchQueries: AnyObject, Sendable {
    /// `IsPlayerInLiveMatch`: archiving is refused while true.
    func isPlayerInLiveMatch(_ player: UUID) -> Bool
    /// `HavePlayedEachOther`: merging is refused while true.
    func havePlayedEachOther(_ a: UUID, _ b: UUID) -> Bool
    /// Matches (any status but deleted) with the player on either side: removing asks first when > 0.
    func matchCount(of player: UUID) -> Int
}
