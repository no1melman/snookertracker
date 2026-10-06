import AppIntents
import Foundation
import LiveActivityShared

// Lock-screen buttons (spec 018). Compiled into both the app and the widget extension (the widget
// needs the types for `Button(intent:)`). As `LiveActivityIntent`s they are performed in the app's
// process, where the composition root has installed `MatchActivityCommandRoute.commands`, so they
// reach the same use cases and database as the app: no App Group or shared container is needed.

struct AwardFrameIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Award Frame"
    static let isDiscoverable = false

    @Parameter(title: "Match") var match: String
    @Parameter(title: "Player") var player: String

    init() {}

    init(match: UUID, player: UUID) {
        self.match = match.uuidString
        self.player = player.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let match = UUID(uuidString: match), let player = UUID(uuidString: player) else { return .result() }
        try MatchActivityCommandRoute.resolve().awardFrame(match: match, to: player)
        return .result()
    }
}

struct PauseMatchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Match"
    static let isDiscoverable = false

    @Parameter(title: "Match") var match: String

    init() {}

    init(match: UUID) {
        self.match = match.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let match = UUID(uuidString: match) else { return .result() }
        try MatchActivityCommandRoute.resolve().pauseMatch(match)
        return .result()
    }
}

struct ResumeMatchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Match"
    static let isDiscoverable = false

    @Parameter(title: "Match") var match: String

    init() {}

    init(match: UUID) {
        self.match = match.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let match = UUID(uuidString: match) else { return .result() }
        try MatchActivityCommandRoute.resolve().resumeMatch(match)
        return .result()
    }
}
