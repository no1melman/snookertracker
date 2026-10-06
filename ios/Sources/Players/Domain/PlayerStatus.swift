import Foundation

/// Lifecycle of a player.
///
/// Allowed transitions, and no others:
/// - Active → Archived | MergedAway
/// - Archived → Active | Removed
public enum PlayerStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case active
    case archived
    case mergedAway
    case removed

    public func canTransition(to next: PlayerStatus) -> Bool {
        switch (self, next) {
        case (.active, .archived), (.active, .mergedAway),
             (.archived, .active), (.archived, .removed):
            true
        default:
            false
        }
    }

    /// Active and archived players hold their name; merged-away and removed players free it.
    public var holdsName: Bool {
        switch self {
        case .active, .archived: true
        case .mergedAway, .removed: false
        }
    }
}
