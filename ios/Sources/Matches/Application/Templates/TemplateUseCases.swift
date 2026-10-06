import EventDispatch
import Foundation
import MatchesDomain
import MatchesPublished
import Observation

/// `TemplateList` read model (spec 008). Holds the stored rows (reloaded after every template
/// change) and resolves names and colours from the Players supplier at read time, so a rename or
/// recolour shows straight away. A template whose player the supplier no longer knows is left out.
@MainActor @Observable
public final class TemplateListProjection: TemplateListQuery {
    private let reader: any TemplateListReader
    private let directory: any MatchPlayerDirectory
    private var entries: [TemplateListEntry] = []

    public init(reader: any TemplateListReader, players: any MatchPlayerDirectory) {
        self.reader = reader
        self.directory = players
    }

    public func reload() throws {
        entries = try reader.templateList()
    }

    public var templates: [TemplateRow] {
        entries.compactMap { entry in
            guard let first = entry.setup.first.ref.flatMap(directory.player),
                  let second = entry.setup.second.ref.flatMap(directory.player)
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

    // MARK: Plumbing

    /// save → refresh. Template events are Stage 1 only, so nothing is dispatched.
    private func commit(_ template: Template) throws {
        try repository.save(template)
        try list.reload()
    }
}
