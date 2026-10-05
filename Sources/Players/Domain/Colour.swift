import Foundation

/// A palette colour for a player. Colours are not unique: two players may share one.
/// Raw values match the UI's `PlayerColour` enum.
public enum Colour: String, CaseIterable, Hashable, Sendable, Codable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray
}

/// The ordered palette new players draw their colour from.
public struct Palette: Hashable, Sendable {
    /// Ordered, non-empty, no duplicates.
    public let colours: [Colour]

    private init(colours: [Colour]) { self.colours = colours }

    /// The app's palette: every `Colour`, in declaration order.
    public static let standard = Palette(colours: Colour.allCases)

    /// The next colour for a new player, given the colours existing players already have.
    ///
    /// The first palette colour nobody uses. When every colour is in use, colours repeat from the
    /// start: the first colour with the fewest users wins, so the 13th player on a 12-colour palette
    /// gets the first colour, the 14th the second, and so on.
    public func nextUnusedColour<S: Sequence>(given used: S) -> Colour where S.Element == Colour {
        var counts: [Colour: Int] = [:]
        for colour in used { counts[colour, default: 0] += 1 }
        // `colours` is non-empty, so `min` always finds one; ties go to the earliest palette position.
        var best = colours[0]
        var bestCount = counts[best, default: 0]
        for colour in colours.dropFirst() {
            let count = counts[colour, default: 0]
            if count < bestCount {
                best = colour
                bestCount = count
            }
        }
        return best
    }
}
