import EventDispatch
import Foundation
import Observation
import PlayersPublished
import StatsDomain
import UpgradePublished

/// `SeriesList` read model (spec 016). Holds the stored rows (reloaded after every series change)
/// and resolves names and colours from the catalog at read time. A setup whose player the catalog no
/// longer knows is left out of the row. Locked while Free (S52): the rows stay stored, the read
/// returns none, and unlocking shows them all again.
@MainActor @Observable
public final class SeriesListProjection: SeriesListQuery {
    @ObservationIgnored private let reader: any SeriesListReader
    @ObservationIgnored private let catalog: any SeriesSetupCatalog
    /// Upgrade's `CurrentEdition` (ADR-0011); Unlocked until the composition root hands it over.
    @ObservationIgnored public var edition: any CurrentEdition
    private var entries: [SeriesListEntry] = []
    /// Bumped on `refresh()` (player events, `AppUnlocked`, `AppLocked`) so rows re-resolve.
    private var generation = 0

    public init(
        reader: any SeriesListReader, catalog: any SeriesSetupCatalog,
        edition: any CurrentEdition = FixedEdition.unlocked
    ) {
        self.reader = reader
        self.catalog = catalog
        self.edition = edition
    }

    public var isLocked: Bool {
        _ = generation
        return !edition.allows(.series)
    }

    public func reload() throws {
        entries = try reader.seriesList()
    }

    public func refresh() {
        catalog.refresh()
        generation += 1
    }

    public var series: [SeriesRow] {
        if isLocked { return [] }
        return entries.map { SeriesRow(id: $0.id, name: $0.name, setups: $0.setups.compactMap(choice)) }
    }

    public func setupChoices(including current: [SetupChoice]) -> [SetupChoice] {
        if isLocked { return [] }
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
    /// Upgrade's `CurrentEdition` open host (ADR-0011): read it before a guarded action. Unlocked
    /// (no limits) until the composition root hands over the device's edition.
    public var edition: any CurrentEdition

    public init(
        repository: any SeriesRepository, list: SeriesListProjection,
        edition: any CurrentEdition = FixedEdition.unlocked,
        newID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.edition = edition
        self.repository = repository
        self.list = list
        self.newID = newID
    }

    /// Rebuilds the list from the store (launch).
    public func loadSeries() throws {
        try list.reload()
    }

    // MARK: CreateSeries (S39)

    /// Series are paid (S39, S40): refused while Free → the upgrade offer (S52).
    private func requireSeries() throws {
        guard edition.allows(.series) else { throw UpgradeRequired(.series) }
    }

    @discardableResult
    public func createSeries(name: String, setups: [SetupChoice]) throws -> UUID {
        try requireSeries()
        let id = SeriesId(newID())
        let series = try Series.create(id: id, name: SeriesName.create(name).get(), setups: setups.map(\.setup)).get()
        try commit(series)
        return id.value
    }

    // MARK: ChangeSeries (S40)

    /// The sheet's result: the new name and the full set of setups.
    public func changeSeries(_ id: UUID, name: String, setups: [SetupChoice]) throws {
        try requireSeries()
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
        try requireSeries()
        guard let series = try repository.getById(SeriesId(id)) else { return }  // already gone
        try commit(series.delete().get())
    }

    // MARK: Policies (run whatever the edition: S33, S42 never wait for an unlock)

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
    /// `AppUnlocked` / `AppLocked` refresh the list so it opens up or locks straight away.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(PlayerEventPublished.self) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        dispatcher.subscribe(AppUnlockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.list.refresh() }
        }
        dispatcher.subscribe(AppLockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.list.refresh() }
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
