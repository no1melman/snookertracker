import Foundation
import StatsDomain

// Series ports (spec 016). Adapters live in StatsInfrastructure/Series.

/// `SeriesRepository`: not event-sourced; one row per series plus its setups. Saving a deleted
/// series removes it (and never touches a match: membership is derived from setups).
public protocol SeriesRepository: Sendable {
    func getById(_ id: SeriesId) throws -> Series?
    func save(_ series: Series) throws
    /// Every series (monthly summaries, S38).
    func findAll() throws -> [Series]
    /// Series with a setup that has `player` on either side (merge repointing S33, removal S42).
    func findContainingPlayer(_ player: UUID) throws -> [Series]
}

/// One stored series as the list reads it: no aggregate, just the stored values.
public struct SeriesListEntry: Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let setups: [Setup]

    public init(id: UUID, name: String, setups: [Setup]) {
        self.id = id; self.name = name; self.setups = setups
    }
}

/// Query port behind `SeriesList`: every series, by name.
public protocol SeriesListReader: Sendable {
    func seriesList() throws -> [SeriesListEntry]
}

/// What the Series screen needs from the rest of Stats: the setups of matches played so far (to
/// pick from) and players as they stand now (names, colours, merges followed). The composition root
/// satisfies it; `StatsStoreSetupCatalog` is a ready-made adapter over the Stats store.
@MainActor public protocol SeriesSetupCatalog: AnyObject {
    /// Distinct setups of recorded matches, most recently played first.
    func knownSetups() -> [Setup]
    /// The player as shown now (a folded-in player resolves to the kept one); nil if unknown.
    func player(_ id: UUID) -> HistoryPlayer?
    /// Re-reads players and setups (after player events or new matches).
    func refresh()
}

// MARK: - Read models (for presentation)

/// A setup as shown: both players, the game, the style and the break rule.
public struct SetupChoice: Identifiable, Hashable, Sendable {
    public var id: String { setup.key }
    public let setup: Setup
    public let first: HistoryPlayer
    public let second: HistoryPlayer
    /// "Pool".
    public let game: String
    /// "Race to 5", "Best of 3 sets · race to 3", "Most frames".
    public let style: String
    /// "Alternate breaks" or "Winner breaks".
    public let breakRule: String

    public init(setup: Setup, first: HistoryPlayer, second: HistoryPlayer) {
        self.setup = setup
        self.first = first
        self.second = second
        game = setup.game.prefix(1).uppercased() + setup.game.dropFirst()
        style = SetupText.style(setup.style)
        breakRule = setup.breakRule == "winnerBreaks" ? "Winner breaks" : "Alternate breaks"
    }

    /// "Pool · Race to 5 · Alternate breaks".
    public var details: String { [game, style, breakRule].joined(separator: " · ") }
    /// "Callum v Asher".
    public var title: String { "\(first.name) v \(second.name)" }
}

/// `SeriesList` row: id, name, setups.
public struct SeriesRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let setups: [SetupChoice]

    public init(id: UUID, name: String, setups: [SetupChoice]) {
        self.id = id; self.name = name; self.setups = setups
    }
}

/// `SeriesList` plus the setups the create/edit sheet offers. Observation-tracked.
@MainActor public protocol SeriesListQuery: AnyObject, Sendable {
    var series: [SeriesRow] { get }
    /// Setups of past matches, plus `including` ones (a series' current setups) not among them.
    func setupChoices(including: [SetupChoice]) -> [SetupChoice]
    /// Re-reads players and known setups.
    func refresh()
}

/// `CreateSeries`, `ChangeSeries`, `DeleteSeries` (Series screen).
@MainActor public protocol SeriesCommands: AnyObject, Sendable {
    @discardableResult func createSeries(name: String, setups: [SetupChoice]) throws -> UUID
    func changeSeries(_ id: UUID, name: String, setups: [SetupChoice]) throws
    func deleteSeries(_ id: UUID) throws
}

enum SetupText {
    static func style(_ style: Setup.Style) -> String {
        func target(_ t: Setup.Target, _ unit: String = "") -> String {
            if let m = t.bestOf { return "best of \(m)\(unit)" }
            return "race to \(t.raceTo)\(unit)"
        }
        let text = switch style {
        case .mostFramesWins: "most frames"
        case .raceTo(let t): target(t)
        case .sets(let sets, let frames): target(sets, " sets") + " · " + target(frames)
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
