import Foundation

// Series (spec 016): a named group of setups. Every past and future match with one of its setups
// belongs to it, so membership is never stored per match and deleting a series never touches a
// match. Not event-sourced: the events below are Stage 1 only and stay inside Stats.

public struct SeriesCreated: Hashable, Sendable {
    public let seriesId: SeriesId
    public let name: SeriesName
    public let setups: [Setup]

    public init(seriesId: SeriesId, name: SeriesName, setups: [Setup]) {
        self.seriesId = seriesId; self.name = name; self.setups = setups
    }
}

/// Renamed and/or setups added or removed (by the scorer, a player merge or a player removal).
public struct SeriesChanged: Hashable, Sendable {
    public let seriesId: SeriesId
    public let name: SeriesName
    public let setups: [Setup]

    public init(seriesId: SeriesId, name: SeriesName, setups: [Setup]) {
        self.seriesId = seriesId; self.name = name; self.setups = setups
    }
}

public struct SeriesDeleted: Hashable, Sendable {
    public let seriesId: SeriesId

    public init(seriesId: SeriesId) { self.seriesId = seriesId }
}

public enum SeriesEvent: Hashable, Sendable {
    case created(SeriesCreated)
    case changed(SeriesChanged)
    case deleted(SeriesDeleted)
}

public enum SeriesError: Error, Equatable, Sendable {
    case invalidId(String)
    /// S39: no name → cannot save.
    case blankName
    /// S39: a series starts with one or more setups.
    case noSetups
    /// Nobody plays themselves.
    case samePlayer(UUID)
    case invalidMonth(Int)
    /// A deleted series takes no further changes.
    case deleted(SeriesId)
}

extension SeriesError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidId(let raw): "\"\(raw)\" isn't a series id."
        case .blankName: "Give the series a name."
        case .noSetups: "Pick at least one setup for the series."
        case .samePlayer: "A setup needs two different players."
        case .invalidMonth(let m): "\(m) isn't a month."
        case .deleted: "That series has been deleted."
        }
    }
}

public struct Series: Hashable, Sendable, Identifiable {
    public let id: SeriesId
    public private(set) var name: SeriesName
    /// Unique (setup equality), in the order they were added. A setup can be in several series.
    public private(set) var setups: [Setup]
    public private(set) var isDeleted: Bool
    public private(set) var uncommittedEvents: [SeriesEvent]

    private init(id: SeriesId, name: SeriesName, setups: [Setup]) {
        self.id = id
        self.name = name
        self.setups = Self.unique(setups)
        isDeleted = false
        uncommittedEvents = []
    }

    /// S39: a named series of one or more setups.
    public static func create(id: SeriesId, name: SeriesName, setups: [Setup]) -> Result<Series, SeriesError> {
        guard !setups.isEmpty else { return .failure(.noSetups) }
        var s = Series(id: id, name: name, setups: setups)
        s.uncommittedEvents = [.created(SeriesCreated(seriesId: id, name: name, setups: s.setups))]
        return .success(s)
    }

    /// A series as stored (persistence only); raises nothing.
    public static func restore(id: SeriesId, name: SeriesName, setups: [Setup]) -> Series {
        Series(id: id, name: name, setups: setups)
    }

    /// S40 (and S33, S42 through the policies): rename and/or add and remove setups. Removals apply
    /// before additions. A change that changes nothing raises nothing, so policies are idempotent.
    /// The series may end up with no setups (its last player removed); the scorer can then edit or
    /// delete it.
    public func change(name newName: SeriesName? = nil, add: [Setup] = [], remove: [Setup] = []) -> Result<Series, SeriesError> {
        guard !isDeleted else { return .failure(.deleted(id)) }
        var s = self
        if let newName { s.name = newName }
        let removing = Set(remove)
        s.setups = Self.unique(setups.filter { !removing.contains($0) } + add)
        if Set(s.setups) == Set(setups) { s.setups = setups }  // same setups: keep their order
        guard s.name != name || s.setups != setups else { return .success(self) }
        s.uncommittedEvents.append(.changed(SeriesChanged(seriesId: id, name: s.name, setups: s.setups)))
        return .success(s)
    }

    /// S33: the folded-in player's setups now name the kept player; setups that become identical
    /// combine into one.
    public func repoint(_ foldedIn: UUID, to kept: UUID) -> Result<Series, SeriesError> {
        let affected = setups.filter { $0.involves(foldedIn) }
        return change(add: affected.compactMap { $0.replacing(foldedIn, with: kept) }, remove: affected)
    }

    /// S42: the removed player's setups are taken out.
    public func removePlayer(_ player: UUID) -> Result<Series, SeriesError> {
        change(remove: setups.filter { $0.involves(player) })
    }

    /// S40: deleting a series never touches matches; membership is only ever derived from setups.
    public func delete() -> Result<Series, SeriesError> {
        guard !isDeleted else { return .failure(.deleted(id)) }
        var s = self
        s.isDeleted = true
        s.uncommittedEvents.append(.deleted(SeriesDeleted(seriesId: id)))
        return .success(s)
    }

    /// Whether a match of `setup` belongs to this series.
    public func covers(_ setup: Setup) -> Bool { !isDeleted && setups.contains(setup) }

    /// The same series once its events are stored.
    public func committed() -> Series {
        var s = self
        s.uncommittedEvents = []
        return s
    }

    private static func unique(_ setups: [Setup]) -> [Setup] {
        var seen = Set<Setup>()
        return setups.filter { seen.insert($0).inserted }
    }
}
