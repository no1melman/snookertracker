import Foundation

// Ports for the Matches context. Implementations are @MainActor @Observable objects, so SwiftUI
// re-renders when a read model changes (reading a property through these protocols is tracked).

// MARK: - Queries (read models, spec 009)

/// `LiveMatches`: one row per live match, oldest started first.
@MainActor public protocol LiveMatchesQuery: AnyObject, Sendable {
    var liveMatches: [LiveMatchRow] { get }
}

/// `LiveMatchScreen`: everything the live screen shows for one match; nil once it has ended.
@MainActor public protocol LiveMatchScreenQuery: AnyObject, Sendable {
    func liveMatchScreen(_ id: MatchID) -> LiveMatchScreen?
}

/// `MatchSettingsView` + `ChangeMatchDefaults` (spec 007).
@MainActor public protocol MatchSettings: AnyObject, Sendable {
    var defaults: MatchDefaults { get }
    var liveMatchLimit: Int { get }
    func changeDefaults(_ defaults: MatchDefaults) throws
    func changeLiveMatchLimit(_ limit: Int)
}

// MARK: - Commands (use cases, spec 010)

/// The live-play use cases: StartMatch, ChooseBreaker, AwardFrame, RemoveFrame, PauseMatch,
/// ResumeMatch, FinishMatch, AbandonMatch, CancelMatch.
@MainActor public protocol MatchCommands: AnyObject, Sendable {
    @discardableResult
    func startMatch(_ setup: MatchSetup) throws -> MatchID
    func chooseBreaker(_ match: MatchID, player: PlayerRef) throws
    func awardFrame(_ match: MatchID, to player: PlayerRef) throws
    func removeFrame(_ match: MatchID, from player: PlayerRef) throws
    func pauseMatch(_ match: MatchID) throws
    func resumeMatch(_ match: MatchID) throws
    /// Finishing a target style short of its target throws `MatchCommandError.finishShortOfTarget`
    /// unless `anyway` (then it counts as abandoned).
    func finishMatch(_ match: MatchID, anyway: Bool) throws
    func abandonMatch(_ match: MatchID) throws
    func cancelMatch(_ match: MatchID) throws
}

// MARK: - Supplier port (Players context, adapted in the composition root)

/// What Matches needs from Players: names and colours, `PlayerSuggestions`, and inline add.
@MainActor public protocol MatchPlayerDirectory: AnyObject, Sendable {
    var suggestions: [MatchPlayer] { get }
    var me: PlayerRef? { get }
    func player(_ id: PlayerRef) -> MatchPlayer?
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer
}

public struct MatchPlayer: Identifiable, Hashable, Sendable {
    public let id: PlayerRef
    public var name: String
    /// Palette key (DesignSystem `PlayerColour` raw value).
    public var colour: String

    public init(id: PlayerRef, name: String, colour: String) {
        self.id = id
        self.name = name
        self.colour = colour
    }
}

public extension MatchCommands {
    func finishMatch(_ match: MatchID) throws { try finishMatch(match, anyway: false) }
}
