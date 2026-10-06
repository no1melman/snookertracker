import Foundation

public enum PlayerNameError: Error, Equatable, Sendable {
    case blank
}

/// A player's name: non-blank (surrounding whitespace is trimmed) and compared case-insensitively,
/// so `"callum" == "Callum"`. `value` keeps the spelling the scorer typed, for display.
public struct PlayerName: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The name as entered (trimmed), for display.
    public let value: String

    /// The case-folded form that equality, hashing and uniqueness use.
    public var comparisonKey: String { value.lowercased() }

    private init(value: String) { self.value = value }

    public static func create(_ raw: String) -> Result<PlayerName, PlayerNameError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.blank) }
        return .success(PlayerName(value: trimmed))
    }

    public static func == (lhs: PlayerName, rhs: PlayerName) -> Bool {
        lhs.comparisonKey == rhs.comparisonKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(comparisonKey)
    }

    public var description: String { value }

    // Encoded as a bare string; decoding re-runs validation.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch PlayerName.create(raw) {
        case .success(let name): self = name
        case .failure: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Blank player name")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
