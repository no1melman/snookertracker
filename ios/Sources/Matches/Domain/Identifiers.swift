import Foundation

/// Why a raw value cannot be an identifier.
public enum IdentifierError: Error, Equatable, Sendable {
    case empty
}

/// Marker for the kind of thing an `OpaqueId` identifies, so the id types cannot be swapped.
public protocol OpaqueIdKind: Sendable {
    static var name: String { get }
}

/// An opaque, non-empty identifier. Use the aliases `MatchId`, `PlayerId`, `TemplateId`.
public struct OpaqueId<Kind: OpaqueIdKind>: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    private init(value: String) { self.value = value }

    /// A fresh id from a UUID supplied by the caller (the domain never generates one).
    public init(_ uuid: UUID) { self.value = uuid.uuidString }

    public static func create(_ raw: String) -> Result<Self, IdentifierError> {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        return .success(Self(value: raw))
    }

    public var description: String { value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch Self.create(raw) {
        case .success(let id): self = id
        case .failure:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Empty \(Kind.name)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public enum MatchIdKind: OpaqueIdKind { public static let name = "MatchId" }
/// Matches' reference to a Players `Player`.
public enum PlayerIdKind: OpaqueIdKind { public static let name = "PlayerId" }
public enum TemplateIdKind: OpaqueIdKind { public static let name = "TemplateId" }

public typealias MatchId = OpaqueId<MatchIdKind>
public typealias PlayerId = OpaqueId<PlayerIdKind>
public typealias TemplateId = OpaqueId<TemplateIdKind>
