import MatchesApplication
import SwiftUI

/// The Matches application ports a view may use, injected by the composition root.
public struct MatchesPorts: Sendable {
    public let live: any LiveMatchesQuery
    public let screens: any LiveMatchScreenQuery
    public let commands: any MatchCommands
    public let settings: any MatchSettings
    public let players: any MatchPlayerDirectory

    public init(
        live: any LiveMatchesQuery, screens: any LiveMatchScreenQuery, commands: any MatchCommands,
        settings: any MatchSettings, players: any MatchPlayerDirectory
    ) {
        self.live = live
        self.screens = screens
        self.commands = commands
        self.settings = settings
        self.players = players
    }
}

public extension EnvironmentValues {
    @Entry var matchesPorts: MatchesPorts? = nil
}

/// Navigation values the hub registers destinations for.
public enum MatchRoute: Hashable {
    case newGame
    case live(MatchID)
}

/// VoiceOver score: "Asher 4, Me 3".
func spokenScore(_ sides: [LiveSide]) -> String {
    sides.map { "\($0.name) \($0.frames)" }.joined(separator: ", ")
}
