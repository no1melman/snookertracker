import DesignSystem
import StatsApplication
import SwiftUI

extension HistoryPlayer {
    /// The plate colour: the player's own, or a neutral one while Free (no colours, ADR-0010).
    var plateColour: Color { showsColour ? PlayerColour.color(colour) : .secondary }
}
