import Foundation

/// Opaque identity of a player. Backed by a UUID, so it can never be empty.
public struct PlayerId: Equatable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: UUID

    public init(_ value: UUID) { self.value = value }

    /// A fresh identity. Called by the application layer; the aggregate takes the id as an argument.
    public static func new() -> PlayerId { PlayerId(UUID()) }

    public var description: String { value.uuidString }

    // Encoded as a bare UUID string, not `{"value": ...}`.
    public init(from decoder: any Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
