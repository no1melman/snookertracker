import Foundation

public enum ColourError: Error, Equatable, Sendable {
    case empty
}

/// Matches' reference to a palette colour (the palette itself belongs to Players).
public struct Colour: Hashable, Sendable, Codable, CustomStringConvertible {
    public let name: String

    private init(name: String) { self.name = name }

    public static func create(_ name: String) -> Result<Colour, ColourError> {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        return .success(Colour(name: name))
    }

    public var description: String { name }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard case .success(let colour) = Colour.create(try c.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Empty Colour")
        }
        self = colour
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(name)
    }
}

/// A player in a match with this match's display colour (which may be a temporary override).
public struct Side: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let colour: Colour

    public init(player: PlayerId, colour: Colour) {
        self.player = player
        self.colour = colour
    }

    func recoloured(_ colour: Colour) -> Side { Side(player: player, colour: colour) }
}
