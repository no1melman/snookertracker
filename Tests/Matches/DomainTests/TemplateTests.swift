import Foundation
import MatchesDomain
import Testing

@Suite("Template")
struct TemplateTests {
    static let id1 = TemplateId.create("template-1").value!
    static let id2 = TemplateId.create("template-2").value!

    static func raceTo5(_ a: PlayerId = Fixture.callum, _ b: PlayerId = Fixture.asher) -> Setup {
        Setup.create(a, b, game: .pool, style: .raceTo(Fixture.target(5))).value!
    }

    @Test func aNewSetupBecomesATemplateUsedOnce() {
        let t = Template.create(id: Self.id1, setup: Self.raceTo5())
        #expect(t.useCount == .one)
        #expect(!t.isDeleted)
        #expect(t.uncommittedEvents == [.created(TemplateCreated(templateId: Self.id1, setup: Self.raceTo5()))])
    }

    @Test func playingAKnownSetupAgainAddsOneUse() {
        let t = Template.create(id: Self.id1, setup: Self.raceTo5()).committed().recordUse().value!.recordUse().value!
        #expect(t.useCount.value == 3)
        #expect(t.uncommittedEvents.last == .used(TemplateUsed(templateId: Self.id1, useCount: t.useCount)))
    }

    @Test func combiningIdenticalTemplatesAddsTheirUseCountsAndDeletesTheAbsorbedOne() {
        let a = Template.restore(id: Self.id1, setup: Self.raceTo5(), useCount: UseCount.create(4).value!)
        // Same setup with the players the other way round.
        let b = Template.restore(id: Self.id2, setup: Self.raceTo5(Fixture.asher, Fixture.callum), useCount: UseCount.create(2).value!)
        let (survivor, absorbed) = a.combine(with: b).value!
        #expect(survivor.useCount.value == 6)
        #expect(!survivor.isDeleted)
        #expect(survivor.uncommittedEvents == [.combined(TemplatesCombined(survivor: Self.id1, absorbed: Self.id2, useCount: survivor.useCount))])
        #expect(absorbed.isDeleted)
        #expect(absorbed.uncommittedEvents == [.deleted(TemplateDeleted(templateId: Self.id2))])
    }

    @Test func templatesForDifferentSetupsCannotBeCombined() {
        let a = Template.create(id: Self.id1, setup: Self.raceTo5())
        let b = Template.create(id: Self.id2, setup: Fixture.setup())
        #expect(a.combine(with: b).error == .differentSetup(Self.id2))
        #expect(a.combine(with: a).error == .sameTemplate(Self.id1))
    }

    @Test func deletingRaisesTemplateDeletedAndEndsTheTemplate() {
        let t = Template.create(id: Self.id1, setup: Self.raceTo5()).committed().delete().value!
        #expect(t.isDeleted)
        #expect(t.uncommittedEvents == [.deleted(TemplateDeleted(templateId: Self.id1))])
        #expect(t.recordUse().error == .deleted(Self.id1))
        #expect(t.delete().error == .deleted(Self.id1))
        #expect(Template.create(id: Self.id2, setup: Self.raceTo5()).combine(with: t).error == .deleted(Self.id1))
    }

    @Test func aKnownSetupRecordsAUseOnItsTemplateInsteadOfCreatingASecond() {
        let existing = Template.restore(id: Self.id1, setup: Self.raceTo5(), useCount: UseCount.create(2).value!)
        // Best of 9 is the same setup as race to 5, entered the other way round.
        let again = Setup.create(Fixture.asher, Fixture.callum, game: .pool, style: .raceTo(Target.bestOf(9).value!)).value!
        let t = TemplateUse.record(again, existing: existing, newId: Self.id2).value!
        #expect(t.id == Self.id1)
        #expect(t.useCount.value == 3)
    }

    @Test func anUnknownSetupGetsANewTemplate() {
        let t = TemplateUse.record(Self.raceTo5(), existing: nil, newId: Self.id2).value!
        #expect(t.id == Self.id2)
        #expect(t.useCount == .one)
    }

    @Test func aTemplateForAnotherSetupIsNeverUsedForThisOne() {
        let other = Template.create(id: Self.id1, setup: Fixture.setup())
        #expect(TemplateUse.record(Self.raceTo5(), existing: other, newId: Self.id2).error == .differentSetup(Self.id1))
    }
}
