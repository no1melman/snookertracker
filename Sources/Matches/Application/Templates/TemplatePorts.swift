import Foundation
import MatchesDomain

// Template ports (spec 008). Adapters live in MatchesInfrastructure/Templates.

public typealias TemplateID = UUID

public enum TemplateRepositoryError: Error, Equatable, Sendable {
    /// Another active template already holds this setup (the one-per-setup invariant's backstop).
    case setupAlreadyHasTemplate
}

/// `TemplateRepository`: not event-sourced; one row per active template. Saving a deleted template
/// removes it, so the setup is free for a new template.
public protocol TemplateRepository: Sendable {
    func getById(_ id: TemplateID) throws -> Template?
    func save(_ template: Template) throws
    /// The active template for that setup (setup equality: unordered players, best-of = race-to).
    func findBySetup(_ setup: Setup) throws -> Template?
    /// Active templates with that player on either side (merge combining, removal cascade: spec 011).
    func findByPlayer(_ player: PlayerRef) throws -> [Template]
}

/// One stored template as the list reads it: no aggregate, just the stored values.
public struct TemplateListEntry: Hashable, Sendable {
    public let id: TemplateID
    public let setup: Setup
    public let useCount: Int

    public init(id: TemplateID, setup: Setup, useCount: Int) {
        self.id = id
        self.setup = setup
        self.useCount = useCount
    }
}

/// Query port behind `TemplateList`: every active template, most used first
/// (ties: most recently used first).
public protocol TemplateListReader: Sendable {
    func templateList() throws -> [TemplateListEntry]
}

// MARK: - Ports for presentation

/// One row of `TemplateList`: both players, the game, the style and targets as entered, the break rule.
public struct TemplateRow: Identifiable, Hashable, Sendable {
    public let id: TemplateID
    /// In the order the setup was first entered.
    public let players: [MatchPlayer]
    public let game: Game
    public let style: MatchStyle
    public let breakRule: BreakRule
    public let useCount: Int

    public init(id: TemplateID, players: [MatchPlayer], game: Game, style: MatchStyle, breakRule: BreakRule, useCount: Int) {
        self.id = id
        self.players = players
        self.game = game
        self.style = style
        self.breakRule = breakRule
        self.useCount = useCount
    }

    /// What `StartMatch` takes to play this template again.
    public var setup: MatchSetup {
        MatchSetup(players: players.map(\.id), game: game, style: style, breakRule: breakRule)
    }
}

/// `TemplateList` (spec 008): most used first. Empty → New Game opens straight on the details step.
@MainActor public protocol TemplateListQuery: AnyObject, Sendable {
    var templates: [TemplateRow] { get }
}

public extension TemplateListQuery {
    /// An empty list routes New Game straight to the details step.
    var opensOnDetails: Bool { templates.isEmpty }
}

/// `DeleteTemplate` (swipe).
@MainActor public protocol TemplateCommands: AnyObject, Sendable {
    func deleteTemplate(_ id: TemplateID) throws
}
