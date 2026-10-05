import Foundation
import Testing
import PlayersDomain

@Suite("PlayerName")
struct PlayerNameTests {
    @Test("a blank name is refused")
    func blankNameRefused() {
        #expect(PlayerName.create("") == .failure(.blank))
        #expect(PlayerName.create("   \n\t") == .failure(.blank))
    }

    @Test("surrounding whitespace is trimmed and the typed spelling kept")
    func trimsAndKeepsSpelling() throws {
        let name = try PlayerName.create("  Callum ").get()
        #expect(name.value == "Callum")
    }

    @Test("names compare case-insensitively")
    func caseInsensitiveEquality() throws {
        let lower = try PlayerName.create("callum").get()
        let upper = try PlayerName.create("Callum").get()
        #expect(lower == upper)
        #expect(Set([lower, upper]).count == 1)
        #expect(try PlayerName.create("Cal").get() != upper)
    }

    @Test("a name round-trips through Codable as a bare string")
    func codableRoundTrip() throws {
        let name = try PlayerName.create("Asher").get()
        let data = try JSONEncoder().encode(name)
        #expect(String(decoding: data, as: UTF8.self) == "\"Asher\"")
        #expect(try JSONDecoder().decode(PlayerName.self, from: data).value == "Asher")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlayerName.self, from: Data("\" \"".utf8))
        }
    }
}

@Suite("Colour and Palette")
struct PaletteTests {
    @Test("colour raw values match the UI palette")
    func rawValues() {
        #expect(Colour.allCases.map(\.rawValue) == [
            "red", "orange", "yellow", "green", "mint", "teal",
            "blue", "indigo", "purple", "pink", "brown", "gray",
        ])
    }

    @Test("the first player gets the first palette colour")
    func firstColour() {
        #expect(Palette.standard.nextUnusedColour(given: []) == .red)
    }

    @Test("the next colour is the first one nobody uses")
    func nextUnused() {
        #expect(Palette.standard.nextUnusedColour(given: [.red, .orange]) == .yellow)
        #expect(Palette.standard.nextUnusedColour(given: [.orange, .yellow]) == .red)
        #expect(Palette.standard.nextUnusedColour(given: [.red, .yellow, .red]) == .orange)
    }

    @Test("when every colour is in use, colours repeat from the start")
    func repeatsWhenExhausted() {
        let all = Colour.allCases
        #expect(Palette.standard.nextUnusedColour(given: all) == .red)
        #expect(Palette.standard.nextUnusedColour(given: all + [.red]) == .orange)
        #expect(Palette.standard.nextUnusedColour(given: all + [.red, .orange]) == .yellow)
        #expect(Palette.standard.nextUnusedColour(given: all + all) == .red)
    }

    @Test("after exhaustion, a colour freed up by a recolour is reused before repeating")
    func leastUsedWins() {
        let used = Colour.allCases + [.red, .orange, .yellow]
        #expect(Palette.standard.nextUnusedColour(given: used) == .green)
    }
}

@Suite("PlayerStatus")
struct PlayerStatusTests {
    static let allowed: Set<[PlayerStatus]> = [
        [.active, .archived], [.active, .mergedAway],
        [.archived, .active], [.archived, .removed],
    ]

    @Test("only Active → Archived | MergedAway and Archived → Active | Removed are allowed",
          arguments: PlayerStatus.allCases, PlayerStatus.allCases)
    func transitionTable(from: PlayerStatus, to: PlayerStatus) {
        #expect(from.canTransition(to: to) == Self.allowed.contains([from, to]))
    }
}

@Suite("MeSetting")
struct MeSettingTests {
    let callum = PlayerId.new()
    let cal = PlayerId.new()

    @Test("Me starts unset and can be set and cleared")
    func setAndClear() {
        #expect(MeSetting.unset.me == nil)
        #expect(!MeSetting.unset.isSet)
        let set = MeSetting.unset.set(callum)
        #expect(set.me == callum)
        #expect(set.clear() == .unset)
    }

    @Test("when Me is folded into another player, Me follows the kept player")
    func followsMerge() {
        let me = MeSetting.unset.set(cal)
        #expect(me.followingMerge(foldedIn: cal, kept: callum).me == callum)
    }

    @Test("a merge of other players leaves Me alone")
    func unrelatedMerge() {
        let me = MeSetting.unset.set(callum)
        #expect(me.followingMerge(foldedIn: cal, kept: .new()) == me)
        #expect(MeSetting.unset.followingMerge(foldedIn: cal, kept: callum) == .unset)
    }

    @Test("removing the Me player clears Me; removing someone else does not")
    func clearedOnRemoval() {
        let me = MeSetting.unset.set(callum)
        #expect(me.clearingOnRemoval(of: callum) == .unset)
        #expect(me.clearingOnRemoval(of: cal) == me)
    }
}
