import XCTest
@testable import CarTV

/// The Pro state comes from the purchases of the account.
@MainActor
final class StoreKitTests: XCTestCase {

    /// AC24: only the Pro product unlocks Pro.
    func test_AC24_only_the_pro_product_unlocks_pro() {
        XCTAssertTrue(StoreKitManager.unlocksPro(transactionIDs: [StoreKitManager.proProductID]))
        XCTAssertFalse(StoreKitManager.unlocksPro(transactionIDs: ["com.example.something_else"]))
        XCTAssertFalse(StoreKitManager.unlocksPro(transactionIDs: []))
    }
}
