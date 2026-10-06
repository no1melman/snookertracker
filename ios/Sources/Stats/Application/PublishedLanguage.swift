import Foundation
import MatchesPublished
import PlayersPublished

// Stats is conformist to Matches' and Players' published language (ADR-0003): it reads the
// versioned JSON payloads as published, taking only the fields it needs (a tolerant reader).
// No Matches or Players types are imported; these mirror the documented wire shapes.

/// A Stage 2 match event as Stats understands it. Events Stats has no use for are `.ignored`.
enum MatchFact {
    case started(Started)
    case frameWon(FrameWon)
    case frameRemoved(frameNumber: Int)
    case paused(at: Date)
    case resumed(at: Date)
    case colourOverridden(player: UUID, colour: String)
    case finished(Finished)
    case abandoned(Abandoned)
    case cancelled(at: Date)
    case scoreCorrected(ScoreCorrected)
    case markedFinished(MarkedFinished)
    case deleted
    case ignored

    struct Side: Decodable { let player: UUID; let colour: String }

    struct Target: Decodable {
        let raceTo: Int
        let bestOf: Int?
        var style: MatchRecord.Target { MatchRecord.Target(raceTo: raceTo, bestOf: bestOf) }
    }

    /// Swift's synthesised enum coding: `{"mostFramesWins":{}}`, `{"raceTo":{"_0":…}}`,
    /// `{"sets":{"sets":…,"frames":…}}`.
    struct Style: Decodable {
        let value: MatchRecord.Style

        private enum Keys: String, CodingKey { case mostFramesWins, raceTo, sets }
        private enum RaceKeys: String, CodingKey { case _0 }
        private enum SetsKeys: String, CodingKey { case sets, frames }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if c.contains(.raceTo) {
                let race = try c.nestedContainer(keyedBy: RaceKeys.self, forKey: .raceTo)
                value = .raceTo(try race.decode(Target.self, forKey: ._0).style)
            } else if c.contains(.sets) {
                let sets = try c.nestedContainer(keyedBy: SetsKeys.self, forKey: .sets)
                value = .sets(sets: try sets.decode(Target.self, forKey: .sets).style,
                              frames: try sets.decode(Target.self, forKey: .frames).style)
            } else {
                value = .mostFramesWins
            }
        }
    }

    struct Setup: Decodable {
        let first: UUID
        let second: UUID
        let game: String
        let style: Style
        let breakRule: String
    }

    struct Started: Decodable { let setup: Setup; let first: Side; let second: Side; let at: Date }

    struct FrameWon: Decodable {
        let player: UUID
        let frameNumber: Int
        let setNumber: Int
        let length: TimeInterval
        let breaker: UUID?
        let at: Date
    }

    struct Score: Decodable {
        struct Sets: Decodable { let firstSets: Int; let secondSets: Int }
        let firstFrames: Int
        let secondFrames: Int
        let sets: Sets?

        var record: MatchRecord.Score {
            MatchRecord.Score(first: firstFrames, second: secondFrames, firstSets: sets?.firstSets, secondSets: sets?.secondSets)
        }
    }

    /// `{"win":{"_0":Side}}` or `{"draw":{}}`.
    struct Result: Decodable {
        let value: MatchRecord.Result

        private enum Keys: String, CodingKey { case win, draw }
        private enum WinKeys: String, CodingKey { case _0 }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if c.contains(.win) {
                let win = try c.nestedContainer(keyedBy: WinKeys.self, forKey: .win)
                value = .win(try win.decode(Side.self, forKey: ._0).player)
            } else {
                value = .draw
            }
        }
    }

    struct Finished: Decodable {
        let result: Result
        let score: Score
        let endedAt: Date
        let length: TimeInterval
        let shortOfTarget: Bool
    }

    struct Abandoned: Decodable { let score: Score; let endedAt: Date; let length: TimeInterval }

    struct ScoreCorrected: Decodable { let before: Score; let after: Score; let result: Result?; let at: Date }

    struct MarkedFinished: Decodable { let result: Result; let at: Date }

    private struct At: Decodable { let at: Date }
    private struct FrameRemovedPayload: Decodable { let frameNumber: Int }
    private struct ColourOverridden: Decodable { let player: UUID; let colour: String }

    /// Decodes one published event. Unknown types are ignored; unknown schema versions throw.
    static func decode(_ e: MatchEventPublished) throws -> MatchFact {
        guard e.schemaVersion == 1 else { throw StatsError.unsupportedSchema(e.type, e.schemaVersion) }
        let p = e.payload
        switch e.type {
        case "MatchStarted": return .started(try json.decode(Started.self, from: p))
        case "FrameWon": return .frameWon(try json.decode(FrameWon.self, from: p))
        case "FrameRemoved": return .frameRemoved(frameNumber: try json.decode(FrameRemovedPayload.self, from: p).frameNumber)
        case "MatchPaused", "MatchAutoPaused": return .paused(at: try json.decode(At.self, from: p).at)
        case "MatchResumed": return .resumed(at: try json.decode(At.self, from: p).at)
        case "MatchColourOverridden":
            let o = try json.decode(ColourOverridden.self, from: p)
            return .colourOverridden(player: o.player, colour: o.colour)
        case "MatchFinished": return .finished(try json.decode(Finished.self, from: p))
        case "MatchAbandoned": return .abandoned(try json.decode(Abandoned.self, from: p))
        case "MatchCancelled": return .cancelled(at: try json.decode(At.self, from: p).at)
        case "MatchScoreCorrected": return .scoreCorrected(try json.decode(ScoreCorrected.self, from: p))
        case "MatchMarkedFinished": return .markedFinished(try json.decode(MarkedFinished.self, from: p))
        case "MatchDeleted": return .deleted
        default: return .ignored
        }
    }

    static var json: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

/// A player event as Stats understands it.
enum PlayerFact {
    case added(id: UUID, name: String, colour: String)
    case renamed(id: UUID, name: String)
    case colourChanged(id: UUID, colour: String)
    case merged(kept: UUID, foldedIn: UUID)
    case archived(UUID)
    case unarchived(UUID)
    case removed(UUID)
    case ignored

    private struct Added: Decodable { let playerId: UUID; let name: String; let colour: String }
    private struct Renamed: Decodable { let playerId: UUID; let newName: String }
    private struct ColourChanged: Decodable { let playerId: UUID; let newColour: String }
    private struct Merged: Decodable { let keptPlayerId: UUID; let foldedInPlayerId: UUID }
    private struct Single: Decodable { let playerId: UUID }

    static func decode(_ e: PlayerEventPublished) throws -> PlayerFact {
        guard e.schemaVersion == 1 else { throw StatsError.unsupportedSchema(e.type, e.schemaVersion) }
        let p = e.payload, json = MatchFact.json
        switch e.type {
        case "PlayerAdded":
            let a = try json.decode(Added.self, from: p)
            return .added(id: a.playerId, name: a.name, colour: a.colour)
        case "PlayerRenamed":
            let r = try json.decode(Renamed.self, from: p)
            return .renamed(id: r.playerId, name: r.newName)
        case "PlayerColourChanged":
            let c = try json.decode(ColourChanged.self, from: p)
            return .colourChanged(id: c.playerId, colour: c.newColour)
        case "PlayersMerged":
            let m = try json.decode(Merged.self, from: p)
            return .merged(kept: m.keptPlayerId, foldedIn: m.foldedInPlayerId)
        case "PlayerArchived": return .archived(try json.decode(Single.self, from: p).playerId)
        case "PlayerUnarchived": return .unarchived(try json.decode(Single.self, from: p).playerId)
        case "PlayerRemoved": return .removed(try json.decode(Single.self, from: p).playerId)
        default: return .ignored
        }
    }
}

public enum StatsError: Error, Equatable, Sendable {
    case unsupportedSchema(String, Int)
}
