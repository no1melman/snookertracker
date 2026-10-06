import Foundation

// Template (spec 008): a setup that has been played, kept so it can be started again in one tap.
// Not event-sourced: the events below are Stage 1 only and stay inside Matches.

public struct TemplateCreated: Hashable, Sendable {
    public let templateId: TemplateId
    public let setup: Setup

    public init(templateId: TemplateId, setup: Setup) { self.templateId = templateId; self.setup = setup }
}

public struct TemplateUsed: Hashable, Sendable {
    public let templateId: TemplateId
    public let useCount: UseCount

    public init(templateId: TemplateId, useCount: UseCount) { self.templateId = templateId; self.useCount = useCount }
}

public struct TemplatesCombined: Hashable, Sendable {
    /// The template that remains, holding both use counts.
    public let survivor: TemplateId
    /// The identical template that was absorbed and deleted.
    public let absorbed: TemplateId
    public let useCount: UseCount

    public init(survivor: TemplateId, absorbed: TemplateId, useCount: UseCount) {
        self.survivor = survivor; self.absorbed = absorbed; self.useCount = useCount
    }
}

public struct TemplateDeleted: Hashable, Sendable {
    public let templateId: TemplateId

    public init(templateId: TemplateId) { self.templateId = templateId }
}

public enum TemplateEvent: Hashable, Sendable {
    case created(TemplateCreated)
    case used(TemplateUsed)
    case combined(TemplatesCombined)
    case deleted(TemplateDeleted)
}

public enum TemplateError: Error, Equatable, Sendable {
    /// A deleted template takes no further changes.
    case deleted(TemplateId)
    /// Only a template for the same setup can be used for, or combined with, it (one per setup).
    case differentSetup(TemplateId)
    /// A template cannot absorb itself.
    case sameTemplate(TemplateId)
}

public struct Template: Hashable, Sendable, Identifiable {
    public let id: TemplateId
    /// The template's identity: at most one active template per setup.
    public let setup: Setup
    public private(set) var useCount: UseCount
    public private(set) var isDeleted: Bool
    public private(set) var uncommittedEvents: [TemplateEvent]

    private init(id: TemplateId, setup: Setup, useCount: UseCount) {
        self.id = id
        self.setup = setup
        self.useCount = useCount
        isDeleted = false
        uncommittedEvents = []
    }

    /// A setup played for the first time (or again after its template was deleted): use count 1.
    public static func create(id: TemplateId, setup: Setup) -> Template {
        var t = Template(id: id, setup: setup, useCount: .one)
        t.uncommittedEvents = [.created(TemplateCreated(templateId: id, setup: setup))]
        return t
    }

    /// An active template as stored (persistence only); raises nothing.
    public static func restore(id: TemplateId, setup: Setup, useCount: UseCount) -> Template {
        Template(id: id, setup: setup, useCount: useCount)
    }

    /// The setup was played again: use count + 1.
    public func recordUse() -> Result<Template, TemplateError> {
        guard !isDeleted else { return .failure(.deleted(id)) }
        var t = self
        t.useCount = useCount.incremented()
        t.uncommittedEvents.append(.used(TemplateUsed(templateId: id, useCount: t.useCount)))
        return .success(t)
    }

    /// Absorbs an identical template (after a player merge made them the same setup): use counts add
    /// and the absorbed one is deleted, so one template per setup remains.
    public func combine(with other: Template) -> Result<(survivor: Template, absorbed: Template), TemplateError> {
        guard !isDeleted else { return .failure(.deleted(id)) }
        guard !other.isDeleted else { return .failure(.deleted(other.id)) }
        guard other.id != id else { return .failure(.sameTemplate(id)) }
        guard other.setup == setup else { return .failure(.differentSetup(other.id)) }
        var survivor = self
        survivor.useCount = useCount.adding(other.useCount)
        survivor.uncommittedEvents.append(.combined(
            TemplatesCombined(survivor: id, absorbed: other.id, useCount: survivor.useCount)))
        var absorbed = other
        absorbed.isDeleted = true
        absorbed.uncommittedEvents.append(.deleted(TemplateDeleted(templateId: other.id)))
        return .success((survivor, absorbed))
    }

    public func delete() -> Result<Template, TemplateError> {
        guard !isDeleted else { return .failure(.deleted(id)) }
        var t = self
        t.isDeleted = true
        t.uncommittedEvents.append(.deleted(TemplateDeleted(templateId: id)))
        return .success(t)
    }

    /// The same template once its events are stored.
    public func committed() -> Template {
        var t = self
        t.uncommittedEvents = []
        return t
    }
}

/// The one-per-setup rule when a match starts: a known setup's template records a use, an unknown
/// setup gets a new template. `existing` is the active template for the setup, if any.
public enum TemplateUse {
    public static func record(
        _ setup: Setup, existing: Template?, newId: TemplateId
    ) -> Result<Template, TemplateError> {
        guard let existing else { return .success(.create(id: newId, setup: setup)) }
        guard existing.setup == setup else { return .failure(.differentSetup(existing.id)) }
        return existing.recordUse()
    }
}
