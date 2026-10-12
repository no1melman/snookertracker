// swift-tools-version: 6.0
// Layering (spec 002): per context, Domain <- Application <- Infrastructure / Presentation.
// Contexts talk only through their *Published modules (events + open-host query protocols).
import PackageDescription

// Upgrade first: it depends on no other context (ADR-0011).
let contexts = ["Upgrade", "Matches", "Players", "Stats"]

/// Which other contexts' published modules each context may see (ADR-0002, ADR-0003).
let publishedDeps: [String: [String]] = [
    "Matches": ["Players", "Stats", "Upgrade"],  // Players: customer/supplier; Stats: HeadToHead OHS
    "Players": ["Matches", "Upgrade"],           // IsPlayerInLiveMatch, HavePlayedEachOther OHS
    "Stats": ["Matches", "Players", "Upgrade"],  // published language, conformist
    // Upgrade -> Matches, Players, Stats: CurrentEdition OHS + AppUnlocked / AppLocked (ADR-0011).
]

/// Upgrade's published module re-exposes its own domain value objects (one Free-limits table, ADR-0011).
let publishedOwnDeps: [String: [String]] = ["Upgrade": ["UpgradeDomain"]]

var targets: [Target] = [
    .target(name: "EventDispatch", path: "Sources/Shared/EventDispatch"),
    .target(name: "DesignSystem", path: "Sources/Shared/DesignSystem"),
    // Thin wrapper over the system SQLite3 module, shared by the infrastructure layers (one DB file per device).
    .target(name: "SQLiteSupport", path: "Sources/Shared/SQLiteSupport"),
    .testTarget(name: "EventDispatchTests", dependencies: ["EventDispatch"], path: "Tests/Shared/EventDispatchTests"),
]

for c in contexts {
    let others = publishedDeps[c, default: []].map { Target.Dependency(stringLiteral: "\($0)Published") }
    targets += [
        .target(
            name: "\(c)Published",
            dependencies: ["EventDispatch"] + publishedOwnDeps[c, default: []].map { Target.Dependency(stringLiteral: $0) },
            path: "Sources/\(c)/Published"),
        .target(name: "\(c)Domain", path: "Sources/\(c)/Domain"),
        .target(
            name: "\(c)Application",
            dependencies: [.target(name: "\(c)Domain"), .target(name: "\(c)Published"), "EventDispatch"] + others,
            path: "Sources/\(c)/Application"),
        .target(
            name: "\(c)Infrastructure",
            dependencies: [.target(name: "\(c)Domain"), .target(name: "\(c)Application"), .target(name: "\(c)Published"), "EventDispatch", "SQLiteSupport"] + others,
            path: "Sources/\(c)/Infrastructure"),
        .target(
            name: "\(c)Presentation",
            dependencies: [.target(name: "\(c)Application"), .target(name: "\(c)Published"), "DesignSystem"] + others,
            path: "Sources/\(c)/Presentation"),
        .testTarget(name: "\(c)DomainTests", dependencies: [.target(name: "\(c)Domain")], path: "Tests/\(c)/DomainTests"),
        .testTarget(
            name: "\(c)IntegrationTests",
            dependencies: [.target(name: "\(c)Domain"), .target(name: "\(c)Application"), .target(name: "\(c)Infrastructure"), .target(name: "\(c)Published"), "EventDispatch", "SQLiteSupport"] + others,
            path: "Tests/\(c)/IntegrationTests"),
    ]
}

// Live Activity content + lock-screen command route, shared by the app and the widget extension (spec 018).
targets.append(.target(name: "LiveActivityShared", path: "Sources/Shared/LiveActivityShared"))

// iOS anti-corruption layer: UserNotifications, ActivityKit + App Intents, app lifecycle.
targets.append(.target(
    name: "iOSAdapters",
    dependencies: contexts.flatMap { [Target.Dependency(stringLiteral: "\($0)Application"), Target.Dependency(stringLiteral: "\($0)Published")] }
        + ["EventDispatch", "LiveActivityShared"],
    path: "Sources/Shared/iOSAdapters"))
// App lifecycle adapter + AutoPauseLiveMatches over real SQLite and a scratch UserDefaults suite (spec 020).
targets.append(.testTarget(
    name: "AppLifecycleTests",
    dependencies: ["iOSAdapters", "MatchesApplication", "MatchesInfrastructure", "MatchesDomain", "EventDispatch", "SQLiteSupport"],
    path: "Tests/Shared/AppLifecycleTests"))
targets.append(.testTarget(
    name: "iOSAdaptersTests",
    dependencies: ["iOSAdapters", "LiveActivityShared", "EventDispatch", "SQLiteSupport", "MatchesApplication", "MatchesDomain", "MatchesInfrastructure"],
    path: "Tests/Shared/iOSAdaptersTests"))

// Stats is conformist to Matches' published language (ADR-0003): these tests feed Stats real Matches
// events (real use cases, the real event store and its open-host replay), not hand-written payloads.
targets.append(.testTarget(
    name: "StatsContractTests",
    dependencies: ["StatsApplication", "StatsInfrastructure", "MatchesDomain", "MatchesApplication",
                   "MatchesInfrastructure", "MatchesPublished", "PlayersPublished", "UpgradePublished", "EventDispatch", "SQLiteSupport"],
    path: "Tests/Stats/ContractTests"))

// Composition root module: wires every context; the Xcode app target is a thin @main over it.
targets.append(.target(
    name: "AppComposition",
    dependencies: ["EventDispatch", "DesignSystem", "iOSAdapters", "LiveActivityShared", "SQLiteSupport"]
        + contexts.flatMap { c in ["Application", "Infrastructure", "Presentation"].map { Target.Dependency(stringLiteral: "\(c)\($0)") } },
    path: "Sources/AppComposition"))

let package = Package(
    name: "SnookerTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AppComposition", targets: ["AppComposition"]),
        // The Live Activity widget extension links only these two (spec 018).
        .library(name: "LiveActivityShared", targets: ["LiveActivityShared"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: targets
)
