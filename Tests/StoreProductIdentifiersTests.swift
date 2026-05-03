import Foundation
import XCTest
@testable import Downward

final class StoreProductIdentifiersTests: XCTestCase {
    func testLocalStoreKitProductIDsMatchAuditedCodeIdentifiers() throws {
        let storeKitURL = try XCTUnwrap(
            Bundle.main.url(forResource: "Downward", withExtension: "storekit")
        )
        let data = try Data(contentsOf: storeKitURL)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        let storeKitProductIDs = Set(
            products.compactMap { product in
                product["productID"] as? String
            }
        )

        XCTAssertEqual(storeKitProductIDs, StoreProductIdentifiers.allProductIDs)
        XCTAssertTrue(storeKitProductIDs.contains(StoreProductIdentifiers.supporterUnlock))
        XCTAssertEqual(
            Set(StoreProductIdentifiers.tipProductIDs),
            [
                StoreProductIdentifiers.tipSmall,
                StoreProductIdentifiers.tipMedium,
                StoreProductIdentifiers.tipLarge,
                StoreProductIdentifiers.tipXLarge,
            ]
        )
    }
}
