import XCTest
import Foundation
@testable import CarTV

/// The local StoreKit configuration has to offer the same product the app looks
/// for, or the purchase path cannot be exercised in the Simulator.
final class StoreKitConfigurationTests: XCTestCase {

    private var configurationURL: URL {
        RepositoryFixture.root.appendingPathComponent("Configuration/DrivePlay.storekit")
    }

    /// AC26: the local StoreKit configuration offers the Pro product the app
    /// looks for, so the purchase path can be tested without a Sandbox account.
    func test_AC26_local_storekit_configuration_offers_the_pro_product() throws {
        try RepositoryFixture.skipUnlessPresent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: configurationURL.path))
        let data = try Data(contentsOf: configurationURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        let ids = products.compactMap { $0["productID"] as? String }
        XCTAssertTrue(ids.contains(StoreKitManager.proProductID), "offered: \(ids)")
    }
}
