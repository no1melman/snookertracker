import Foundation
import StatsDomain
import Testing

private let callum = UUID()
private let asher = UUID()

private func month(_ y: Int, _ m: Int) -> Month { try! Month.create(year: y, month: m).get() }

private func fridays() -> Series {
    let setup = try! Setup.create(callum, asher, game: "pool", style: .raceTo(.init(raceTo: 5)), breakRule: "alternate").get()
    return try! Series.create(id: SeriesId(UUID()), name: SeriesName.create("Fridays").get(), setups: [setup]).get().committed()
}

@Suite("Series monthly summary guard")
struct SeriesSummaryTests {
    @Test func aMonthWithMatchesIssuesASummary() throws {
        let series = fridays()
        let issued = try series.issueSummary(for: month(2026, 9), matchesInMonth: 2, currentMonth: month(2026, 10)).get()
        #expect(issued == SeriesSummaryIssued(seriesId: series.id, name: series.name, month: month(2026, 9)))
        // Issuing changes nothing on the series.
        #expect(series.uncommittedEvents.isEmpty)
    }

    @Test func aMonthWithoutMatchesIssuesNothing() {
        let series = fridays()
        let result = series.issueSummary(for: month(2026, 9), matchesInMonth: 0, currentMonth: month(2026, 10))
        #expect(throws: SeriesSummaryError.noMatches(series.id, month(2026, 9))) { try result.get() }
    }

    @Test func onlyAMonthThatIsOverIsSummarised() {
        let series = fridays()
        #expect(throws: SeriesSummaryError.monthNotOver(month(2026, 10))) {
            try series.issueSummary(for: month(2026, 10), matchesInMonth: 3, currentMonth: month(2026, 10)).get()
        }
        // December's summary is issued in January.
        #expect((try? series.issueSummary(for: month(2025, 12), matchesInMonth: 1, currentMonth: month(2026, 1)).get()) != nil)
    }

    @Test func aDeletedSeriesGetsNoSummary() throws {
        let deleted = try fridays().delete().get()
        #expect(throws: SeriesSummaryError.deleted(deleted.id)) {
            try deleted.issueSummary(for: month(2026, 9), matchesInMonth: 1, currentMonth: month(2026, 10)).get()
        }
    }
}
