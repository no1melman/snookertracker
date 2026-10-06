import MatchesApplication
import SwiftUI

/// The Matches application ports a view may use, injected by the composition root.
public struct MatchesPorts: Sendable {
    public let live: any LiveMatchesQuery
    public let screens: any LiveMatchScreenQuery
    public let commands: any MatchCommands
    public let settings: any MatchSettings
    public let players: any MatchPlayerDirectory
    /// `TemplateList` and `DeleteTemplate` (spec 008); nil shows New Game without templates.
    public let templates: (any TemplateListQuery)?
    public let templateCommands: (any TemplateCommands)?
    /// Stats' `HeadToHead` (S14) for the live screen's strip; nil hides the strip.
    public let headToHead: HeadToHeadLookup?

    public init(
        live: any LiveMatchesQuery, screens: any LiveMatchScreenQuery, commands: any MatchCommands,
        settings: any MatchSettings, players: any MatchPlayerDirectory,
        templates: (any TemplateListQuery)? = nil, templateCommands: (any TemplateCommands)? = nil,
        headToHead: HeadToHeadLookup? = nil
    ) {
        self.live = live
        self.screens = screens
        self.commands = commands
        self.settings = settings
        self.players = players
        self.templates = templates
        self.templateCommands = templateCommands
        self.headToHead = headToHead
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

/// VoiceOver score: "Asher 4, Me 3" (sets: "Asher 2 (1 set), Me 0 (0 sets)").
func spokenScore(_ sides: [LiveSide]) -> String { spokenLiveScore(sides) }
