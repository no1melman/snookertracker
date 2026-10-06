import Foundation
import MatchesDomain

/// The versioned wire format of match events: a stable type name, a schema version and a JSON
/// payload. Used by the event store and for the published (Stage 2) events, so both share one contract.
///
/// Type names are written once and never change. A changed payload shape gets a new schema version
/// here, and `decode` keeps reading every older version. The switch is exhaustive, so a new domain
/// event does not compile until it has a wire name.
public enum MatchEventWire {
    public static let currentSchemaVersion = 1

    public struct Encoded: Hashable, Sendable {
        public let type: String
        public let schemaVersion: Int
        public let payload: Data
    }

    public enum WireError: Error, Equatable, Sendable {
        case unknownType(String, schemaVersion: Int)
    }

    public static func encode(_ event: MatchEvent) throws -> Encoded {
        let (type, payload): (String, Data) = switch event {
        case .matchStarted(let e): ("MatchStarted", try encoder.encode(e))
        case .breakerChosen(let e): ("BreakerChosen", try encoder.encode(e))
        case .breakerCorrected(let e): ("BreakerCorrected", try encoder.encode(e))
        case .frameWon(let e): ("FrameWon", try encoder.encode(e))
        case .setWon(let e): ("SetWon", try encoder.encode(e))
        case .matchTargetReached(let e): ("MatchTargetReached", try encoder.encode(e))
        case .frameRemoved(let e): ("FrameRemoved", try encoder.encode(e))
        case .matchPaused(let e): ("MatchPaused", try encoder.encode(e))
        case .matchAutoPaused(let e): ("MatchAutoPaused", try encoder.encode(e))
        case .matchResumed(let e): ("MatchResumed", try encoder.encode(e))
        case .matchColourOverridden(let e): ("MatchColourOverridden", try encoder.encode(e))
        case .matchFinished(let e): ("MatchFinished", try encoder.encode(e))
        case .matchAbandoned(let e): ("MatchAbandoned", try encoder.encode(e))
        case .matchCancelled(let e): ("MatchCancelled", try encoder.encode(e))
        case .staleMatchFlagged(let e): ("StaleMatchFlagged", try encoder.encode(e))
        case .longFrameWarned(let e): ("LongFrameWarned", try encoder.encode(e))
        case .matchScoreCorrected(let e): ("MatchScoreCorrected", try encoder.encode(e))
        case .matchMarkedFinished(let e): ("MatchMarkedFinished", try encoder.encode(e))
        case .matchDeleted(let e): ("MatchDeleted", try encoder.encode(e))
        case .matchPlayerMoved(let e): ("MatchPlayerMoved", try encoder.encode(e))
        }
        return Encoded(type: type, schemaVersion: currentSchemaVersion, payload: payload)
    }

    /// Stage 1 events stay inside Matches: they are stored but not published.
    public static func isPublished(_ event: MatchEvent) -> Bool {
        if case .staleMatchFlagged = event { return false }
        return true
    }

    public static func decode(type: String, schemaVersion: Int, payload: Data) throws -> MatchEvent {
        guard schemaVersion == 1 else { throw WireError.unknownType(type, schemaVersion: schemaVersion) }
        switch type {
        case "MatchStarted": return .matchStarted(try decoder.decode(MatchStarted.self, from: payload))
        case "BreakerChosen": return .breakerChosen(try decoder.decode(BreakerChosen.self, from: payload))
        case "BreakerCorrected": return .breakerCorrected(try decoder.decode(BreakerCorrected.self, from: payload))
        case "FrameWon": return .frameWon(try decoder.decode(FrameWon.self, from: payload))
        case "SetWon": return .setWon(try decoder.decode(SetWon.self, from: payload))
        case "MatchTargetReached": return .matchTargetReached(try decoder.decode(MatchTargetReached.self, from: payload))
        case "FrameRemoved": return .frameRemoved(try decoder.decode(FrameRemoved.self, from: payload))
        case "MatchPaused": return .matchPaused(try decoder.decode(MatchPaused.self, from: payload))
        case "MatchAutoPaused": return .matchAutoPaused(try decoder.decode(MatchAutoPaused.self, from: payload))
        case "MatchResumed": return .matchResumed(try decoder.decode(MatchResumed.self, from: payload))
        case "MatchColourOverridden": return .matchColourOverridden(try decoder.decode(MatchColourOverridden.self, from: payload))
        case "MatchFinished": return .matchFinished(try decoder.decode(MatchFinished.self, from: payload))
        case "MatchAbandoned": return .matchAbandoned(try decoder.decode(MatchAbandoned.self, from: payload))
        case "MatchCancelled": return .matchCancelled(try decoder.decode(MatchCancelled.self, from: payload))
        case "StaleMatchFlagged": return .staleMatchFlagged(try decoder.decode(StaleMatchFlagged.self, from: payload))
        case "LongFrameWarned": return .longFrameWarned(try decoder.decode(LongFrameWarned.self, from: payload))
        case "MatchScoreCorrected": return .matchScoreCorrected(try decoder.decode(MatchScoreCorrected.self, from: payload))
        case "MatchMarkedFinished": return .matchMarkedFinished(try decoder.decode(MatchMarkedFinished.self, from: payload))
        case "MatchDeleted": return .matchDeleted(try decoder.decode(MatchDeleted.self, from: payload))
        case "MatchPlayerMoved": return .matchPlayerMoved(try decoder.decode(MatchPlayerMoved.self, from: payload))
        default: throw WireError.unknownType(type, schemaVersion: schemaVersion)
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = .sortedKeys
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
