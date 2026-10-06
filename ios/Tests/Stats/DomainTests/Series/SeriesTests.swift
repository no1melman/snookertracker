import Foundation
import StatsDomain
import Testing

private let callum = UUID()
private let cal = UUID()
private let asher = UUID()
private let dev = UUID()

private extension Result {
    var value: Success? { try? get() }
    var error: Failure? { if case .failure(let e) = self { e } else { nil } }
}

private func setup(_ a: UUID = callum, _ b: UUID = asher, raceTo n: Int = 5, bestOf: Int? = nil, game: String = "pool") -> Setup {
    Setup.create(a, b, game: game, style: .raceTo(.init(raceTo: n, bestOf: bestOf)), breakRule: "alternate").value!
}

private func name(_ raw: String) -> SeriesName { SeriesName.create(raw).value! }

@Suite("Series value objects")
struct SeriesValueTests {
    @Test func aNameIsTrimmedAndNeverBlank() {
        #expect(SeriesName.create("  Fridays with Asher ").value?.value == "Fridays with Asher")
        #expect(SeriesName.create("   ").error == .blankName)
        #expect(SeriesName.create("").error == .blankName)
    }

    @Test func aSeriesIdIsAUUID() {
        let id = UUID()
        #expect(SeriesId.create(id.uuidString).value == SeriesId(id))
        #expect(SeriesId.create("").error == .invalidId(""))
    }

    @Test func setupEqualityIgnoresPlayerOrderAndHowTheTargetWasEntered() {
        #expect(setup(callum, asher) == setup(asher, callum))
        #expect(setup(raceTo: 5) == setup(raceTo: 5, bestOf: 9))
        #expect(setup(raceTo: 5).key == setup(asher, callum, raceTo: 5, bestOf: 9).key)
        #expect(setup(raceTo: 5) != setup(raceTo: 3))
        #expect(setup(game: "pool") != setup(game: "snooker"))
        #expect(setup(callum, asher) != setup(callum, dev))
    }

    @Test func nobodyPlaysThemselves() {
        #expect(Setup.create(callum, callum, game: "pool", style: .mostFramesWins, breakRule: "alternate").error == .samePlayer(callum))
        #expect(setup(cal, callum).replacing(cal, with: callum) == nil)
    }

    @Test func aMonthIsACalendarMonth() {
        #expect(Month.create(year: 2026, month: 13).error == .invalidMonth(13))
        let oct = Month.create(year: 2026, month: 10).value!
        #expect(oct.previous == Month.create(year: 2026, month: 9).value)
        #expect(Month.create(year: 2026, month: 1).value!.previous == Month.create(year: 2025, month: 12).value)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        #expect(Month.containing(date, calendar: utc) == oct)
        #expect(oct.contains(date, calendar: utc))
        #expect(oct.description == "2026-10")
    }
}

@Suite("Series")
struct SeriesTests {
    static let id = SeriesId(UUID())

    static func fridays(_ setups: [Setup] = [setup()]) -> Series {
        Series.create(id: id, name: name("Fridays with Asher"), setups: setups).value!
    }

    @Test func creatingRaisesSeriesCreated() {
        let s = Self.fridays([setup(), setup(callum, dev)])
        #expect(s.name.value == "Fridays with Asher")
        #expect(s.setups == [setup(), setup(callum, dev)])
        #expect(!s.isDeleted)
        #expect(s.uncommittedEvents == [.created(SeriesCreated(seriesId: Self.id, name: name("Fridays with Asher"), setups: s.setups))])
    }

    @Test func aSeriesNeedsAtLeastOneSetup() {
        #expect(Series.create(id: Self.id, name: name("Empty"), setups: []).error == .noSetups)
    }

    @Test func theSameSetupIsHeldOnce() {
        let s = Self.fridays([setup(callum, asher), setup(asher, callum, raceTo: 5, bestOf: 9)])
        #expect(s.setups.count == 1)
    }

    @Test func aSetupCanBeInSeveralSeries() {
        let a = Self.fridays()
        let b = Series.create(id: SeriesId(UUID()), name: name("All pool"), setups: [setup()]).value!
        #expect(a.covers(setup()) && b.covers(setup()))
    }

    @Test func changingRenamesAddsAndRemovesAndRaisesSeriesChanged() {
        let s = Self.fridays([setup(), setup(callum, dev)]).committed()
            .change(name: name("Thursdays"), add: [setup(asher, dev)], remove: [setup(callum, dev)]).value!
        #expect(s.name.value == "Thursdays")
        #expect(s.setups == [setup(), setup(asher, dev)])
        #expect(s.uncommittedEvents == [.changed(SeriesChanged(seriesId: Self.id, name: name("Thursdays"), setups: s.setups))])
    }

    @Test func aChangeThatChangesNothingRaisesNothing() {
        let s = Self.fridays().committed()
        #expect(s.change(name: name("Fridays with Asher"), add: [setup(asher, callum)]).value!.uncommittedEvents.isEmpty)
        #expect(s.change(remove: [setup(callum, dev)]).value!.uncommittedEvents.isEmpty)
    }

    @Test func repointingAMergeMovesSetupsToTheKeptPlayerAndCombinesDuplicates() {
        let s = Self.fridays([setup(cal, asher), setup(callum, asher), setup(cal, dev)]).committed()
            .repoint(cal, to: callum).value!
        #expect(Set(s.setups) == [setup(callum, asher), setup(callum, dev)])
        #expect(s.setups.count == 2)
        #expect(s.uncommittedEvents.count == 1)
        guard case .changed = s.uncommittedEvents.first else { Issue.record("expected SeriesChanged"); return }
    }

    @Test func removingAPlayerTakesTheirSetupsOutAndMayLeaveTheSeriesEmpty() {
        let s = Self.fridays([setup(), setup(callum, dev)]).committed().removePlayer(dev).value!
        #expect(s.setups == [setup()])
        let empty = s.committed().removePlayer(asher).value!
        #expect(empty.setups.isEmpty)
        #expect(!empty.isDeleted)
        #expect(s.committed().removePlayer(cal).value!.uncommittedEvents.isEmpty)
    }

    @Test func deletingRaisesSeriesDeletedAndEndsTheSeries() {
        let s = Self.fridays().committed().delete().value!
        #expect(s.isDeleted)
        #expect(s.uncommittedEvents == [.deleted(SeriesDeleted(seriesId: Self.id))])
        #expect(!s.covers(setup()))
        #expect(s.change(name: name("Again")).error == .deleted(Self.id))
        #expect(s.delete().error == .deleted(Self.id))
    }

    @Test func restoringRaisesNothing() {
        let s = Series.restore(id: Self.id, name: name("Stored"), setups: [setup()])
        #expect(s.uncommittedEvents.isEmpty)
    }
}
