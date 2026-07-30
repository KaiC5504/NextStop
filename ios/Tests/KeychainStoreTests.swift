import XCTest
@testable import NextStop

final class KeychainStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainStore.delete()
    }

    override func tearDown() {
        KeychainStore.delete()
        super.tearDown()
    }

    /// Settings opens automatically when this returns nil, so it is load-bearing.
    func testReadReturnsNilWhenNothingStored() {
        XCTAssertNil(KeychainStore.read())
    }

    func testSavingTwiceOverwrites() throws {
        try KeychainStore.save("first")
        try KeychainStore.save("second")
        XCTAssertEqual(KeychainStore.read(), "second")
    }
}
