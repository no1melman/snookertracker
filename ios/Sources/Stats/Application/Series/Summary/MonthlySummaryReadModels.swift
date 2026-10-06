import Foundation
import StatsDomain

// `MonthlySummary(series, month)` (spec 017, S38): the Stats figures for a series in one month,
// per pairing, or "you" when Me is in the series, with the change since the previous month.
// Presentation-facing: no domain types (months are given by any date inside them).

/// Which months have had their summary issued, so each is issued once.
public protocol SeriesSummaryLog: Sendable {
    func isIssued(_ series: SeriesId, _ month: Month) throws -> Bool
    func markIssued(_ series: SeriesId, _ month: Month, at: Date) throws
}

/// One line of a monthly summary: "you", or one pairing seen from its first player's side.
public struct MonthlySummaryLine: Identifiable, Hashable, Sendable {
    public enum Subject: Hashable, Sendable {
        /// Me: every match of the series Me played that month, against anyone.
        case you(HistoryPlayer)
        /// Two players of one of the series' setups, the first player's side.
        case pairing(HistoryPlayer, HistoryPlayer)
    }

    public var id: String {
        switch subject {
        case .you(let me): "you:\(me.id)"
        case .pairing(let a, let b): "pair:\(a.id):\(b.id)"
        }
    }

    public let subject: Subject
    public let figures: StatsFigures
    /// The same line's figures for the month before.
    public let previous: StatsFigures

    public init(subject: Subject, figures: StatsFigures, previous: StatsFigures) {
        self.subject = subject; self.figures = figures; self.previous = previous
    }

    public var change: MonthlyChange { MonthlyChange(figures, since: previous) }

    /// "you" or "Callum v Asher".
    public var title: String {
        switch subject {
        case .you: "you"
        case .pairing(let a, let b): "\(a.name) v \(b.name)"
        }
    }

    /// "3–1" (won–lost), or "3–1–1" (won–drawn–lost) once there is a draw.
    public var matchRecord: String { MonthlySummaryText.record(figures) }

    /// "you 3–1 in matches, 22–17 in frames".
    public var headline: String {
        "\(title) \(matchRecord) in matches, \(figures.framesWon)–\(figures.framesLost) in frames"
    }
}

/// Change since the previous month: this month minus last month.
public struct MonthlyChange: Hashable, Sendable {
    public let won: Int
    public let drawn: Int
    public let lost: Int
    public let framesWon: Int
    public let framesLost: Int
    public let decidersWon: Int
    public let decidersLost: Int
    /// Win % this month minus last month; nil when either month has no result.
    public let winPercentagePoints: Double?
    /// No matches the month before: nothing to compare with.
    public let isFirstMonth: Bool

    public init(_ now: StatsFigures, since before: StatsFigures) {
        won = now.won - before.won
        drawn = now.drawn - before.drawn
        lost = now.lost - before.lost
        framesWon = now.framesWon - before.framesWon
        framesLost = now.framesLost - before.framesLost
        decidersWon = now.decidersWon - before.decidersWon
        decidersLost = now.decidersLost - before.decidersLost
        winPercentagePoints = now.winPercentage.flatMap { n in before.winPercentage.map { n - $0 } }
        isFirstMonth = before.matches == 0
    }
}

/// A series' summary for one month.
public struct MonthlySummary: Hashable, Sendable {
    public let seriesId: UUID
    public let seriesName: String
    /// First instant of the month.
    public let monthStart: Date
    public let year: Int
    /// 1...12.
    public let month: Int
    /// "September 2026".
    public let title: String
    /// "September".
    public let monthName: String
    /// "August".
    public let previousMonthName: String
    /// First instant of the month before and the month after (for stepping through months).
    public let previousMonthStart: Date
    public let nextMonthStart: Date
    /// Lines with matches this month: "you" first (when Me is in the series), then the pairings
    /// that do not involve Me, in the order the series lists their setups.
    public let lines: [MonthlySummaryLine]

    public init(
        seriesId: UUID, seriesName: String, monthStart: Date, year: Int, month: Int, title: String, monthName: String,
        previousMonthName: String, previousMonthStart: Date, nextMonthStart: Date, lines: [MonthlySummaryLine]
    ) {
        self.seriesId = seriesId; self.seriesName = seriesName; self.monthStart = monthStart; self.year = year
        self.month = month; self.title = title; self.monthName = monthName; self.previousMonthName = previousMonthName
        self.previousMonthStart = previousMonthStart; self.nextMonthStart = nextMonthStart; self.lines = lines
    }

    /// Matches counted this month (lines never overlap).
    public var matches: Int { lines.reduce(0) { $0 + $1.figures.matches } }
    public var isEmpty: Bool { matches == 0 }

    /// For the notification: the single line's figures, or a count across pairings.
    public var headline: String {
        if lines.count == 1, let line = lines.first { return line.headline }
        return "\(matches) match\(matches == 1 ? "" : "es") across \(lines.count) pairing\(lines.count == 1 ? "" : "s")"
    }
}

/// `MonthlySummary(series, month)` for the screen. Observation flows through `Stats(filter)`.
@MainActor public protocol MonthlySummaryQuery: AnyObject, Sendable {
    /// The summary for the month containing `date`; nil when the series no longer exists.
    func summary(series: UUID, monthOf date: Date) -> MonthlySummary?
    /// The month the latest summary covers: the one before now (the screen opens on it).
    func lastMonth() -> Date
}

enum MonthlySummaryText {
    static func record(_ f: StatsFigures) -> String {
        f.drawn == 0 ? "\(f.won)–\(f.lost)" : "\(f.won)–\(f.drawn)–\(f.lost)"
    }
}
