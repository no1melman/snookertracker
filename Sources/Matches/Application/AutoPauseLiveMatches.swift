import Foundation
import MatchesDomain

/// `AutoPauseLiveMatches` (S27, ADR-0004, ADR-0005): the app-lifecycle trigger. Called on launch when the
/// lifecycle adapter detects that the last session was killed rather than returned to the foreground.
/// Runs before anything reads live matches, and before `FlagStaleMatches` (S28).
@MainActor public protocol LiveMatchAutoPausing: AnyObject, Sendable {
    /// Pauses each running live match at the later of `lastBackgroundAt` and its last action
    /// (its last action when no background time was recorded). Returns the matches it paused.
    @discardableResult
    func autoPauseLiveMatches(lastBackgroundAt: Date?) throws -> [MatchID]
}

extension MatchUseCases: LiveMatchAutoPausing {
    @discardableResult
    public func autoPauseLiveMatches(lastBackgroundAt: Date?) throws -> [MatchID] {
        var paused: [MatchID] = []
        for match in try repository.findLive() {
            // Lock-screen actions can come after backgrounding, so never stamp the pause before one.
            let at = max(lastBackgroundAt ?? match.lastActionAt, match.lastActionAt)
            switch match.autoPause(at: at) {
            case .success(let changed):
                try commit(changed)
                if let id = match.id.uuid { paused.append(id) }
            case .failure(.notAllowed):
                continue  // already paused, or waiting on a confirmation: untouched
            case .failure(let error):
                throw MatchCommandError(error)
            }
        }
        return paused
    }
}
