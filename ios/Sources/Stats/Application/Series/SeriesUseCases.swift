import EventDispatch
import Foundation
import Observation
import PlayersPublished
import StatsDomain

/// `SeriesList` read model (spec 016). Holds the stored rows (reloaded after every series change)
/// and resolves names and colours from the catalog at read time. A setup whose player the catalog no
/// longer knows is left out of the row.
@MainActor @Observable
public final class SeriesListProjection: SeriesListQuery {
    @ObservationIgnored private let reader: any SeriesListReader
    @ObservationIgnored private let catalog: any SeriesSetupCatalog
    private var entries: [SeriesListEntry] = []
    /// Bumped on `refresh()` so rows re-resolve players.
    private var generation = 0

    public init(reader: any SeriesListReader, catalog: any SeriesSetupCatalog) {
        self.reader = reader
        self.catalog = catalog
    }

    public func reload() throws {
        entries = try reader.seriesList()
    }

    public func refresh() {
        catalog.refresh()
        generation += 1
    }

    public var series: [SeriesRow] {
        _ = generation
        return entries.map { SeriesRow(id: $0.id, name: $0.name, setups: $0.setups.compactMap(choice)) }
    }

    public func setupChoices(including current: [SetupChoice]) -> [SetupChoice] {
        _ = generation
        let known = catalog.knownSetups().compactMap(choice)
        let knownSetups = Set(known.map(\.setup))
        return known + current.filter { !knownSetups.contains($0.setup) }
    }

    private func choice(_ setup: Setup) -> SetupChoice? {
        guard let a = catalog.player(setup.first), let b = catalog.player(setup.second) else { return nil }
        return SetupChoice(setup: setup, first: a, second: b)
    }
}

/// The series use cases (spec 016): `CreateSeries`, `ChangeSeries`, `DeleteSeries` (Series screen)
/// and the policies `RepointSeriesOnMerge` (`PlayersMerged`) and `RemovePlayerFromSeries`
/// (`PlayerRemoved`). Each one is load → domain behaviour → save → refresh the list. Series events
/// are Stage 1 only, so nothing is dispatched.
@MainActor
public final class SeriesUseCases: SeriesCommands {
    private let repository: any SeriesRepository
    private let list: SeriesListProjection
    private let newID: @Sendable () -> UUID
    /// The last policy failure (a policy never throws into a Players command).
    public private(set) var lastError: (any Error)?

    public init(
        repository: any SeriesRepository, list: SeriesListProjection,
        newID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.list = list
        self.newID = newID
    }

    /// Rebuilds the list from the store (launch).
    public func loadSeries() throws {
        try list.reload()
    }

    // MARK: CreateSeries (S39)

    @discardableResult
    public func createSeries(name: String, setups: [SetupChoice]) throws -> UUID {
        let id = SeriesId(newID())
        let series = try Series.create(id: id, name: SeriesName.create(name).get(), setups: setups.map(\.setup)).get()
        try commit(series)
        return id.value
    }

    // MARK: ChangeSeries (S40)

    /// The sheet's result: the new name and the full set of setups.
    public func changeSeries(_ id: UUID, name: String, setups: [SetupChoice]) throws {
        guard let series = try repository.getById(SeriesId(id)) else { throw SeriesError.deleted(SeriesId(id)) }
        let wanted = setups.map(\.setup)
        guard !wanted.isEmpty else { throw SeriesError.noSetups }
        let keep = Set(wanted)
        let changed = try series.change(
            name: SeriesName.create(name).get(),
            add: wanted.filter { !series.setups.contains($0) },
            remove: series.setups.filter { !keep.contains($0) }).get()
        try commit(changed)
    }

    // MARK: DeleteSeries (S40)

    public func deleteSeries(_ id: UUID) throws {
        guard let series = try repository.getById(SeriesId(id)) else { return }  // already gone
        try commit(series.delete().get())
    }

    // MARK: Policies

    /// RepointSeriesOnMerge (S33): the folded-in player's setups now name the kept player.
    public func repointSeriesOnMerge(kept: UUID, foldedIn: UUID) throws {
        for series in try repository.findContainingPlayer(foldedIn) {
            try commit(series.repoint(foldedIn, to: kept).get())
        }
    }

    /// RemovePlayerFromSeries (S42): the removed player's setups are taken out of every series.
    public func removePlayerFromSeries(_ player: UUID) throws {
        for series in try repository.findContainingPlayer(player) {
            try commit(series.removePlayer(player).get())
        }
    }

    /// Subscribes both policies to Players' published events. Any player event also refreshes the
    /// names and colours the list shows. A failure is kept in `lastError`, never thrown into Players.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(PlayerEventPublished.self) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
    }

    public func receive(_ event: PlayerEventPublished) {
        do {
            switch try PlayerFact.decode(event) {
            case .merged(let kept, let foldedIn): try repointSeriesOnMerge(kept: kept, foldedIn: foldedIn)
            case .removed(let player): try removePlayerFromSeries(player)
            default: break
            }
        } catch {
            lastError = error
        }
        list.refresh()
    }

    // MARK: Plumbing

    private func commit(_ series: Series) throws {
        guard !series.uncommittedEvents.isEmpty else { return }  // nothing changed
        try repository.save(series)
        try list.reload()
    }
}
