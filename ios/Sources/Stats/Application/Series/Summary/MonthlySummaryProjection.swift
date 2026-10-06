import Foundation
import StatsDomain

/// `MonthlySummary(series, month)` (spec 017, S38) over `Stats(filter)` with the series filter and
/// the month as the date range: no aggregate, figures exactly as the Stats screen counts them
/// (finished matches; archived players' matches included; a match is in the month it started in).
/// It is worked out each time it is read, so a match recorded late still shows (Q5).
@MainActor
public final class MonthlySummaryProjection: MonthlySummaryQuery {
    private let stats: any StatsQuery
    private let series: any SeriesListReader
    private let me: @MainActor () -> UUID?
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    /// `me` is Players' `WhoAmI`, adapted by the composition root; `now` is the clock.
    public init(
        stats: any StatsQuery, series: any SeriesListReader, me: @escaping @MainActor () -> UUID?,
        now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current
    ) {
        self.stats = stats
        self.series = series
        self.me = me
        self.now = now
        self.calendar = calendar
    }

    // MARK: MonthlySummaryQuery

    public func summary(series id: UUID, monthOf date: Date) -> MonthlySummary? {
        summary(series: id, month: Month.containing(date, calendar: calendar))
    }

    public func lastMonth() -> Date {
        start(of: Month.containing(now(), calendar: calendar).previous)
    }

    // MARK: For IssueMonthlySummaries

    public func summary(series id: UUID, month: Month) -> MonthlySummary? {
        guard let entry = try? series.seriesList().first(where: { $0.id == id }) else { return nil }
        let filter = SeriesFilter(seriesId: entry.id, name: entry.name, setups: Set(entry.setups))
        let known = Dictionary(stats.statsPlayers(includeArchived: true).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var pairings: [(UUID, UUID)] = []
        var seen = Set<Set<UUID>>()
        for s in entry.setups where seen.insert(s.players).inserted { pairings.append((s.first, s.second)) }

        func figures(_ pov: UUID, against opponent: UUID?, in m: Month) -> StatsFigures {
            stats.stats(StatsFilter(
                pointOfView: pov, opponent: opponent, dates: interval(of: m),
                includeArchivedPlayers: true, series: filter)).overall
        }

        var lines: [MonthlySummaryLine] = []
        let you = me().flatMap { id in pairings.contains { $0.0 == id || $0.1 == id } ? known[id] : nil }
        if let you {
            lines.append(MonthlySummaryLine(
                subject: .you(you), figures: figures(you.id, against: nil, in: month),
                previous: figures(you.id, against: nil, in: month.previous)))
        }
        for (a, b) in pairings where a != you?.id && b != you?.id {
            guard let first = known[a], let second = known[b] else { continue }
            lines.append(MonthlySummaryLine(
                subject: .pairing(first, second), figures: figures(a, against: b, in: month),
                previous: figures(a, against: b, in: month.previous)))
        }

        let symbols = calendar.standaloneMonthSymbols
        return MonthlySummary(
            seriesId: entry.id, seriesName: entry.name, monthStart: start(of: month), year: month.year, month: month.month,
            title: "\(symbols[month.month - 1]) \(month.year)", monthName: symbols[month.month - 1],
            previousMonthName: symbols[month.previous.month - 1], previousMonthStart: start(of: month.previous),
            nextMonthStart: start(of: month.next), lines: lines.filter { $0.figures.matches > 0 })
    }

    // MARK: Months as dates

    func start(of month: Month) -> Date {
        calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .distantPast
    }

    /// The month as a date range; its end stops just short of the next month's first instant.
    func interval(of month: Month) -> DateInterval {
        let start = start(of: month)
        return DateInterval(start: start, end: max(start, self.start(of: month.next).addingTimeInterval(-0.001)))
    }
}
