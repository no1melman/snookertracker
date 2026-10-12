import StatsApplication
import UpgradePublished
import SwiftUI

/// The Stats application ports a view may use, injected by the composition root.
public struct StatsPorts: Sendable {
    public let history: any MatchHistoryQuery
    /// Matches' `DeleteMatch` (S30), adapted by the composition root; nil hides delete.
    public let deleteMatch: (@MainActor @Sendable (UUID) throws -> Void)?
    /// `Stats(filter)` (spec 014); nil shows the Stats screen as unavailable.
    public let stats: (any StatsQuery)?
    /// Players' `WhoAmI`: the default point of view; nil (or returning nil) asks for a player.
    public let me: (@MainActor @Sendable () -> UUID?)?
    /// Upgrade's `CurrentEdition` (ADR-0011); Unlocked when not handed over.
    public let edition: any CurrentEdition
    /// Routes a refused paid feature to Upgrade's `ShowUpgradeOffer` (S52); a no-op when not handed over.
    public let showUpgradeOffer: ShowUpgradeOfferAction

    public init(
        history: any MatchHistoryQuery, deleteMatch: (@MainActor @Sendable (UUID) throws -> Void)? = nil,
        stats: (any StatsQuery)? = nil, me: (@MainActor @Sendable () -> UUID?)? = nil,
        edition: any CurrentEdition = FixedEdition.unlocked, showUpgradeOffer: @escaping ShowUpgradeOfferAction = { _ in }
    ) {
        self.edition = edition
        self.showUpgradeOffer = showUpgradeOffer
        self.history = history
        self.deleteMatch = deleteMatch
        self.stats = stats
        self.me = me
    }
}

public extension EnvironmentValues {
    @Entry var statsPorts: StatsPorts? = nil
}

/// Navigation values History pushes.
public enum StatsRoute: Hashable {
    case match(UUID)
}

// MARK: Formatting

enum HistoryFormat {
    /// "Fri 3 Oct, 19:30".
    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// "October 2026".
    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func game(_ raw: String) -> String { raw.prefix(1).uppercased() + raw.dropFirst() }

    static func breakRule(_ raw: String) -> String {
        raw == "winnerBreaks" ? "Winner breaks" : "Alternate breaks"
    }

    static func spokenScore(_ row: PastMatchRow) -> String {
        "\(row.first.name) \(row.score.first), \(row.second.name) \(row.score.second)"
    }
}
