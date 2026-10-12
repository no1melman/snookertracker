import Foundation

/// The match styles, as Upgrade names them for the Free limits. Upgrade depends on nothing in the
/// core (ADR-0011): Matches maps its own `MatchStyle` onto these to check a setup.
public enum MatchStyleKind: String, CaseIterable, Hashable, Sendable, Codable {
    case mostFramesWins
    case raceTo
    case sets
}

/// The break rules, as Upgrade names them for the Free limits. Matches maps its `BreakRule` onto these.
public enum BreakRuleKind: String, CaseIterable, Hashable, Sendable, Codable {
    case alternate
    case winnerBreaks
}

/// What the Free edition allows (ADR-0010). One table, owned by Upgrade (ADR-0011): a pricing change
/// is a change to `standard` only. Each context enforces it on its own data.
public struct FreeLimits: Hashable, Sendable {
    /// Live matches at a time (S11, S43, S44).
    public let liveMatches: Int
    /// Active players, Me included; archived players don't count (S3, S33–S35).
    public let activePlayers: Int
    /// The newest ended matches shown; older ones are hidden, never deleted (S17, S29, S30).
    public let visibleEndedMatches: Int
    public let allowedStyles: Set<MatchStyleKind>
    public let allowedBreakRules: Set<BreakRuleKind>

    public init(
        liveMatches: Int, activePlayers: Int, visibleEndedMatches: Int,
        allowedStyles: Set<MatchStyleKind>, allowedBreakRules: Set<BreakRuleKind>
    ) {
        self.liveMatches = liveMatches
        self.activePlayers = activePlayers
        self.visibleEndedMatches = visibleEndedMatches
        self.allowedStyles = allowedStyles
        self.allowedBreakRules = allowedBreakRules
    }

    /// The Free edition's limits.
    public static let standard = FreeLimits(
        liveMatches: 1, activePlayers: 5, visibleEndedMatches: 10,
        allowedStyles: [.mostFramesWins], allowedBreakRules: [.alternate])

    public func allows(_ style: MatchStyleKind) -> Bool { allowedStyles.contains(style) }
    public func allows(_ breakRule: BreakRuleKind) -> Bool { allowedBreakRules.contains(breakRule) }

    /// Free plays most frames wins only.
    public var allowsOnlyMostFramesWins: Bool { allowedStyles == [.mostFramesWins] }
    /// Free plays alternate breaks only.
    public var allowsOnlyAlternateBreaks: Bool { allowedBreakRules == [.alternate] }

    /// Whether one more live match may start, given how many are live now.
    public func allowsAnotherLiveMatch(liveCount: Int) -> Bool { liveCount < liveMatches }
    /// Whether one more player may become active (add, unarchive), given how many are active now.
    public func allowsAnotherActivePlayer(activeCount: Int) -> Bool { activeCount < activePlayers }
}
