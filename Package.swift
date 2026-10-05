// swift-tools-version: 6.0
// Layering (spec 002): per context, Domain <- Application <- Infrastructure / Presentation.
// Contexts talk only through their *Published modules (events + open-host query protocols).
import PackageDescription

let contexts = ["Matches", "Players", "Stats"]

/// Which other contexts' published modules each context may see (ADR-0002, ADR-0003).
let publishedDeps: [String: [String]] = [
    "Matches": ["Players", "Stats"],  // Players: customer/supplier; Stats: HeadToHead OHS
    "Players": ["Matches"],           // IsPlayerInLiveMatch, HavePlayedEachOther OHS
    "Stats": ["Matches", "Players"],  // published language, conformist
]

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
        .target(name: "\(c)Published", dependencies: ["EventDispatch"], path: "Sources/\(c)/Published"),
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
            dependencies: [.target(name: "\(c)Application"), "DesignSystem"],
            path: "Sources/\(c)/Presentation"),
        .testTarget(name: "\(c)DomainTests", dependencies: [.target(name: "\(c)Domain")], path: "Tests/\(c)/DomainTests"),
        .testTarget(
            name: "\(c)IntegrationTests",
            dependencies: [.target(name: "\(c)Domain"), .target(name: "\(c)Application"), .target(name: "\(c)Infrastructure"), .target(name: "\(c)Published"), "EventDispatch", "SQLiteSupport"],
            path: "Tests/\(c)/IntegrationTests"),
    ]
}

// iOS anti-corruption layer: UserNotifications, ActivityKit + App Intents, app lifecycle.
targets.append(.target(
    name: "iOSAdapters",
    dependencies: contexts.flatMap { [Target.Dependency(stringLiteral: "\($0)Application"), Target.Dependency(stringLiteral: "\($0)Published")] },
    path: "Sources/Shared/iOSAdapters"))

// Composition root module: wires every context; the Xcode app target is a thin @main over it.
targets.append(.target(
    name: "AppComposition",
    dependencies: ["EventDispatch", "DesignSystem", "iOSAdapters", "SQLiteSupport"]
        + contexts.flatMap { c in ["Application", "Infrastructure", "Presentation"].map { Target.Dependency(stringLiteral: "\(c)\($0)") } },
    path: "Sources/AppComposition"))

let package = Package(
    name: "SnookerTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AppComposition", targets: ["AppComposition"])],
    targets: targets
)
