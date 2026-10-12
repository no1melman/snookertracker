import Foundation
import UpgradePublished

/// One line on the benefits screen (S53): what the purchase unlocks, in plain language, and what
/// Free allows today. Counts come from `FreeLimits.standard`, so a pricing change updates the copy.
public struct UpgradeBenefit: Hashable, Sendable, Identifiable {
    /// The paid features this line covers (race to and sets share one line).
    public let features: [PaidFeature]
    public let title: String
    /// What Free allows instead, when that is more than nothing.
    public let freeAllows: String?
    public let systemImage: String

    public var id: String { title }
}

public extension UpgradeBenefit {
    /// Every paid feature, once, in the order S53 lists them.
    static var all: [UpgradeBenefit] { all(.standard) }

    /// Every paid feature, once, with the Free side of each line drawn from `limits`.
    static func all(_ limits: FreeLimits) -> [UpgradeBenefit] {
        [
            UpgradeBenefit(
                features: [.severalLiveMatches], title: "Several live matches at once",
                freeAllows: limits.liveMatches == 1 ? "Free: 1 live match" : "Free: \(limits.liveMatches) live matches",
                systemImage: "square.stack"),
            UpgradeBenefit(
                features: [.raceTo, .sets], title: "Race to and sets",
                freeAllows: limits.allowsOnlyMostFramesWins ? "Free: most frames wins only" : nil,
                systemImage: "flag.checkered"),
            UpgradeBenefit(
                features: [.winnerBreaks], title: "Winner breaks",
                freeAllows: limits.allowsOnlyAlternateBreaks ? "Free: alternate breaks only" : nil,
                systemImage: "arrow.triangle.2.circlepath"),
            UpgradeBenefit(
                features: [.extraPlayers], title: "Unlimited players",
                freeAllows: "Free: \(limits.activePlayers) active players (Me included, archived not counted)",
                systemImage: "person.3"),
            UpgradeBenefit(
                features: [.fullHistory], title: "Your full history",
                freeAllows: "Free: newest \(limits.visibleEndedMatches) ended matches shown",
                systemImage: "clock.arrow.circlepath"),
            UpgradeBenefit(features: [.colours], title: "Player colours", freeAllows: nil, systemImage: "paintpalette"),
            UpgradeBenefit(features: [.templates], title: "Templates", freeAllows: nil, systemImage: "rectangle.stack"),
            UpgradeBenefit(features: [.manualPause], title: "Pause by hand", freeAllows: nil, systemImage: "pause.circle"),
            UpgradeBenefit(features: [.headToHead], title: "Head-to-head", freeAllows: nil, systemImage: "person.line.dotted.person"),
            UpgradeBenefit(features: [.stats], title: "Stats", freeAllows: nil, systemImage: "chart.bar"),
            UpgradeBenefit(features: [.series], title: "Series", freeAllows: nil, systemImage: "calendar"),
            UpgradeBenefit(features: [.lockScreen], title: "Lock screen scores", freeAllows: nil, systemImage: "lock.iphone"),
        ]
    }

    /// The small print under the list: what stays free, and that nothing is ever lost.
    static let freeNote = "Auto-pause when the app is closed, and resuming from it, stay free. "
        + "Nothing you record is ever deleted to fit the Free limits: hidden matches, colours and "
        + "templates are all there when you upgrade."
}

public extension PaidFeature {
    /// The feature as the offer names it: "Templates are part of the full version."
    var offerTitle: String {
        switch self {
        case .templates: "Templates"
        case .manualPause: "Pausing a match"
        case .raceTo: "Race to"
        case .sets: "Sets"
        case .winnerBreaks: "Winner breaks"
        case .extraPlayers: "More players"
        case .fullHistory: "Your full history"
        case .colours: "Player colours"
        case .headToHead: "Head-to-head"
        case .stats: "Stats"
        case .series: "Series"
        case .severalLiveMatches: "Several live matches"
        case .lockScreen: "Lock screen scores"
        }
    }

    /// One plain sentence for the offer's callout.
    var offerMessage: String {
        let verb = switch self {
        case .templates, .colours, .stats, .series, .sets, .extraPlayers, .severalLiveMatches, .lockScreen: "are"
        default: "is"
        }
        return "\(offerTitle) \(verb) part of the full version."
    }
}
