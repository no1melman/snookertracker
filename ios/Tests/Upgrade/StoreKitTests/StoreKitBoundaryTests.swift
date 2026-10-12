import Foundation
import Testing
import UpgradeApplication
import UpgradeDomain
@testable import UpgradeInfrastructure

/// ios/, found from this source file.
private let iosRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite struct StoreKitBoundaryTests {
    /// ADR-0011: StoreKit appears only in Upgrade's infrastructure adapter; every other module sees
    /// `AppStorePort`, `CurrentEdition`, `AppUnlocked` and `AppLocked`.
    @Test func storeKitIsImportedOnlyByTheUpgradeAdapter() throws {
        let allowed = iosRoot.appending(path: "Sources/Upgrade/Infrastructure/AppStore").standardizedFileURL.path
        var importers: [String] = []
        for folder in ["Sources", "App", "LiveActivityWidget"] {
            let root = iosRoot.appending(path: folder)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                let importsStoreKit = source.split(separator: "\n").contains { line in
                    let words = line.split(whereSeparator: \.isWhitespace)
                    guard let i = words.firstIndex(of: "import"), i + 1 < words.count else { return false }
                    return words[i + 1].hasPrefix("StoreKit")
                }
                if importsStoreKit { importers.append(file.standardizedFileURL.path) }
            }
        }
        #expect(!importers.isEmpty, "the adapter itself imports StoreKit; the scan found nothing")
        #expect(importers.allSatisfy { $0.hasPrefix(allowed + "/") }, "StoreKit imported outside the adapter: \(importers)")
    }

    /// The product id is set once (`UnlockProductId.fullVersion`); the configuration file must match.
    @Test func theStoreKitConfigurationSellsTheOneUnlock() throws {
        struct Configuration: Decodable {
            struct Product: Decodable { let productID: String; let type: String; let familyShareable: Bool }
            let products: [Product]
        }
        let data = try Data(contentsOf: iosRoot.appending(path: "StoreKit/SnookerTracker.storekit"))
        let products = try JSONDecoder().decode(Configuration.self, from: data).products
        #expect(products.count == 1)
        #expect(products.first?.productID == UnlockProductId.fullVersion.value)
        #expect(products.first?.type == "NonConsumable")
        #expect(products.first?.familyShareable == true)
    }

    /// A launch check that finishes after a live revocation must not re-unlock.
    @Test func aLiveUpdateBeatsAStaleLaunchCheck() async {
        let (stream, continuation) = AsyncStream<AppStoreTransactionUpdate>.makeStream()
        let gate = LaunchGate(continuation)
        gate.yieldLive(.revoked)
        gate.yieldLaunch(.verified)
        continuation.finish()
        var delivered: [AppStoreTransactionUpdate] = []
        for await update in stream { delivered.append(update) }
        #expect(delivered == [.revoked])

        let (first, firstContinuation) = AsyncStream<AppStoreTransactionUpdate>.makeStream()
        let launchFirst = LaunchGate(firstContinuation)
        launchFirst.yieldLaunch(.verified)
        launchFirst.yieldLive(.revoked)
        firstContinuation.finish()
        delivered = []
        for await update in first { delivered.append(update) }
        #expect(delivered == [.verified, .revoked])
    }

    /// Only a verified transaction for the unlock counts; revoked → lock.
    @Test func onlyVerifiedUnlockTransactionsCount() {
        #expect(TransactionReading.update(isUnlock: true, isVerified: true, isRevoked: false) == .verified)
        #expect(TransactionReading.update(isUnlock: true, isVerified: true, isRevoked: true) == .revoked)
        #expect(TransactionReading.update(isUnlock: true, isVerified: false, isRevoked: false) == nil)
        #expect(TransactionReading.update(isUnlock: true, isVerified: false, isRevoked: true) == nil)
        #expect(TransactionReading.update(isUnlock: false, isVerified: true, isRevoked: false) == nil)
    }
}
