import EventDispatch
import Foundation
import MatchesDomain
import MatchesPublished
import Observation

/// `TemplateList` read model (spec 008). Holds the stored rows (reloaded after every template
/// change) and resolves names and colours from the Players supplier at read time, so a rename or
/// recolour shows straight away. A template whose player the supplier no longer knows is left out,
/// and so is one with an archived player (S34), until they are unarchived (S35).
@MainActor @Observable
public final class TemplateListProjection: TemplateListQuery {
    private let reader: any TemplateListReader
    private let directory: any MatchPlayerDirectory
    private var entries: [TemplateListEntry] = []
    /// Archived players: seeded at launch, then kept by `HideArchivedPlayersTemplates`.
    private var archived: Set<PlayerRef> = []

    public init(reader: any TemplateListReader, players: any MatchPlayerDirectory) {
        self.reader = reader
        self.directory = players
    }

    public func reload() throws {
        entries = try reader.templateList()
    }

    /// The players archived at launch (the composition root reads them from Players).
    public func seedArchived(_ players: some Sequence<PlayerRef>) {
        archived = Set(players)
    }

    /// `PlayerArchived`: their templates are hidden.
    public func hideTemplates(of player: PlayerRef) {
        archived.insert(player)
    }

    /// `PlayerUnarchived` (or removed): their templates show again (removed ones are already gone).
    public func showTemplates(of player: PlayerRef) {
        archived.remove(player)
    }

    public var templates: [TemplateRow] {
        entries.compactMap { entry in
            guard let firstRef = entry.setup.first.ref, let secondRef = entry.setup.second.ref,
                  !archived.contains(firstRef), !archived.contains(secondRef),
                  let first = directory.player(firstRef),
                  let second = directory.player(secondRef)
            else { return nil }
            return TemplateRow(
                id: entry.id, players: [first, second], game: Game(entry.setup.game),
                style: MatchStyle(entry.setup.style), breakRule: BreakRule(entry.setup.breakRule),
                useCount: entry.useCount)
        }
    }
}

/// The template use cases (spec 008): `CreateOrUseTemplate` (policy on `MatchStarted`) and
/// `DeleteTemplate` (swipe). Each one is load → domain behaviour → save → refresh the list.
@MainActor
public final class TemplateUseCases: TemplateCommands {
    private let repository: any TemplateRepository
    private let list: TemplateListProjection
    private let newID: @Sendable () -> UUID

    public init(
        repository: any TemplateRepository, list: TemplateListProjection,
        newID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.list = list
        self.newID = newID
    }

    /// Rebuilds the list from the store (launch).
    public func loadTemplates() throws {
        try list.reload()
    }

    // MARK: CreateOrUseTemplate

    /// A match with `setup` started: its template records a use, or one is created with use count 1.
    public func createOrUseTemplate(for setup: Setup) throws {
        let existing = try repository.findBySetup(setup)
        switch TemplateUse.record(setup, existing: existing, newId: TemplateId(newID())) {
        case .success(let template): try commit(template)
        case .failure(let error): throw error
        }
    }

    /// The policy: after a `MatchStarted` is stored and published, create or use its template.
    /// A template failure never undoes or blocks the match; the next start tries again.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(MatchEventPublished.self) { [weak self] published in
            guard published.type == "MatchStarted",
                  case .matchStarted(let started)? = try? MatchEventWire.decode(
                      type: published.type, schemaVersion: published.schemaVersion, payload: published.payload)
            else { return }
            MainActor.assumeIsolated {
                try? self?.createOrUseTemplate(for: started.setup)
            }
        }
    }

    // MARK: DeleteTemplate

    public func deleteTemplate(_ id: TemplateID) throws {
        guard let template = try repository.getById(id) else { return }  // already gone: nothing to do
        switch template.delete() {
        case .success(let deleted): try commit(deleted)
        case .failure(let error): throw error
        }
    }

    // MARK: Player reactions (spec 011)

    /// `DeleteTemplate` for each template of a removed player (S42).
    public func deleteTemplates(of player: PlayerRef) throws {
        for template in try repository.findByPlayer(player) {
            if case .success(let deleted) = template.delete() { try save(deleted) }
        }
        try list.reload()
    }

    /// `CombineTemplatesAfterMerge` (S33): each of the folded-in player's templates moves to the kept
    /// player; one that now equals a kept template is absorbed by it (use counts add). A template of
    /// the two of them together can't survive the merge (it would be a player against themselves),
    /// so it is deleted.
    public func combineTemplatesAfterMerge(kept: PlayerRef, foldedIn: PlayerRef) throws {
        let from = PlayerId(ref: foldedIn), to = PlayerId(ref: kept)
        for template in try repository.findByPlayer(foldedIn) {
            switch template.movePlayer(from: from, to: to) {
            case .success(let moved):
                if let existing = try repository.findBySetup(moved.setup), existing.id != moved.id {
                    switch existing.combine(with: moved) {
                    case .success(let (survivor, absorbed)):
                        try save(absorbed)
                        try save(survivor)
                    case .failure(let error): throw error
                    }
                } else {
                    try save(moved)
                }
            case .failure(.wouldPlayThemselves):
                if case .success(let deleted) = template.delete() { try save(deleted) }
            case .failure(let error): throw error
            }
        }
        try list.reload()
    }

    // MARK: Plumbing

    private func save(_ template: Template) throws {
        try repository.save(template)
    }

    /// save → refresh. Template events are Stage 1 only, so nothing is dispatched.
    private func commit(_ template: Template) throws {
        try repository.save(template)
        try list.reload()
    }
}
