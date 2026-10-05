import Foundation

public enum TargetError: Error, Equatable, Sendable {
    case notPositive(Int)
    case bestOfEven(Int)
}

/// Race to N frames (or sets), N ≥ 1. Entered as "race to N" or "best of M" (M odd, stored ⌈M/2⌉);
/// remembers how it was entered for display. Equality is on N only.
public struct Target: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Entry: Hashable, Sendable, Codable {
        case raceTo
        case bestOf(Int)
    }

    /// N: the number of frames (or sets) needed to win.
    public let value: Int
    public let entry: Entry

    private init(value: Int, entry: Entry) {
        self.value = value
        self.entry = entry
    }

    public static func raceTo(_ n: Int) -> Result<Target, TargetError> {
        guard n >= 1 else { return .failure(.notPositive(n)) }
        return .success(Target(value: n, entry: .raceTo))
    }

    public static func bestOf(_ m: Int) -> Result<Target, TargetError> {
        guard m >= 1 else { return .failure(.notPositive(m)) }
        guard m % 2 == 1 else { return .failure(.bestOfEven(m)) }
        return .success(Target(value: (m + 1) / 2, entry: .bestOf(m)))
    }

    public static func == (lhs: Target, rhs: Target) -> Bool { lhs.value == rhs.value }
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }

    /// Shown as entered: "race to 3" or "best of 5".
    public var description: String {
        switch entry {
        case .raceTo: "race to \(value)"
        case .bestOf(let m): "best of \(m)"
        }
    }

    private enum CodingKeys: String, CodingKey { case raceTo, bestOf }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let result: Result<Target, TargetError>
        if let m = try c.decodeIfPresent(Int.self, forKey: .bestOf) {
            result = Target.bestOf(m)
        } else {
            result = Target.raceTo(try c.decode(Int.self, forKey: .raceTo))
        }
        switch result {
        case .success(let t): self = t
        case .failure(let e):
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Invalid Target: \(e)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .raceTo)
        if case .bestOf(let m) = entry { try c.encode(m, forKey: .bestOf) }
    }
}
