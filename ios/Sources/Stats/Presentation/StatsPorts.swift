import StatsApplication
import SwiftUI

/// The Stats application ports a view may use, injected by the composition root.
public struct StatsPorts: Sendable {
    public let history: any MatchHistoryQuery

    public init(history: any MatchHistoryQuery) {
        self.history = history
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
