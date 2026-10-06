import Foundation
import Observation

/// The stale prompts still waiting for an answer, one at a time (S28). The composition root fills it
/// on launch (`flag()`, in `AppLaunchSequence`'s `afterAutoPause`); the prompt shows `current` and
/// sends the choice back through `resolve`.
@MainActor @Observable
public final class StaleMatchQueue {
    public private(set) var pending: [StaleMatchPrompt] = []
    @ObservationIgnored private let commands: any StaleMatchCommands

    public init(commands: any StaleMatchCommands) {
        self.commands = commands
    }

    /// The match being asked about now.
    public var current: StaleMatchPrompt? { pending.first }

    /// `FlagStaleMatches`: replaces the queue with every stale live match, in prompt order.
    public func flag() throws {
        pending = try commands.flagStaleMatches()
    }

    /// `ResolveStaleMatch` for the current match, then moves on to the next. A match that is no
    /// longer stale (ended or played meanwhile) is skipped without an error. Any other refusal,
    /// including `finishShortOfTarget` (ask, then pass `anyway`), is rethrown and the match stays.
    public func resolve(_ choice: StaleChoice, anyway: Bool = false) throws {
        guard let match = current else { return }
        do {
            try commands.resolveStaleMatch(match.id, choice, anyway: anyway)
        } catch StaleMatchError.noLongerStale {
            // Nothing to resolve any more: fall through and move on.
        }
        pending.removeAll { $0.id == match.id }
    }
}
