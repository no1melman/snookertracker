import Foundation

/// The lifecycle of a match, with exactly the transitions in the requirements.
public enum MatchStatus: String, Hashable, Sendable, Codable, CaseIterable {
    case awaitingBreaker
    case inPlay
    case awaitingConfirmation
    case paused
    case finished
    case abandoned
    case cancelled
    case deleted

    public var allowedTransitions: Set<MatchStatus> {
        switch self {
        case .awaitingBreaker: [.inPlay, .paused, .finished, .abandoned, .cancelled]
        case .inPlay: [.inPlay, .awaitingConfirmation, .paused, .finished, .abandoned, .cancelled]
        case .awaitingConfirmation: [.inPlay, .finished]
        case .paused: [.inPlay, .awaitingBreaker, .finished, .abandoned, .cancelled]
        case .abandoned: [.finished, .deleted]
        case .finished: [.deleted]
        case .cancelled: [.deleted]
        case .deleted: []
        }
    }

    public func canTransition(to next: MatchStatus) -> Bool { allowedTransitions.contains(next) }

    /// Not yet finished, abandoned, cancelled or deleted.
    public var isLive: Bool {
        switch self {
        case .awaitingBreaker, .inPlay, .awaitingConfirmation, .paused: true
        case .finished, .abandoned, .cancelled, .deleted: false
        }
    }
}
