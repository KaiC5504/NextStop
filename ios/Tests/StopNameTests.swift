import XCTest
@testable import NextStop

final class StopNameTests: XCTestCase {
    func testStripsPlatformStandAndWharfSuffixes() {
        XCTAssertEqual(StopName.short("Artarmon Station, Platform 2"), "Artarmon Station")
        XCTAssertEqual(StopName.short("Chatswood Interchange, Stand B"), "Chatswood Interchange")
        XCTAssertEqual(StopName.short("Circular Quay, Wharf 4"), "Circular Quay")
        XCTAssertEqual(StopName.platform("Artarmon Station, Platform 2"), "Platform 2")
        XCTAssertEqual(StopName.platform("Chatswood Interchange, Stand B"), "Stand B")
        XCTAssertEqual(StopName.platform("Circular Quay, Wharf 4"), "Wharf 4")
    }

    func testPassesUnsuffixedNamesThrough() {
        XCTAssertEqual(StopName.short("Central Station"), "Central Station")
        XCTAssertNil(StopName.platform("Central Station"))
    }

    func testNonSuffixCommaSegmentsAreKept() {
        XCTAssertEqual(StopName.short("Museum of Sydney, City"), "Museum of Sydney, City")
        XCTAssertNil(StopName.platform("Museum of Sydney, City"))
    }

    func testCaseInsensitiveMatch() {
        XCTAssertEqual(StopName.short("Town Hall, platform 3"), "Town Hall")
        XCTAssertEqual(StopName.platform("Town Hall, platform 3"), "platform 3")
    }

    /// A name that IS only a suffix has nothing left to show once stripped.
    func testBareSuffixNamePassesThrough() {
        XCTAssertEqual(StopName.short("Platform 2"), "Platform 2")
        XCTAssertNil(StopName.platform("Platform 2"))
    }

    func testOnlyTheLastSegmentIsInspected() {
        XCTAssertEqual(StopName.short("Wynyard, Carrington St, Stand E"), "Wynyard, Carrington St")
        XCTAssertEqual(StopName.platform("Wynyard, Carrington St, Stand E"), "Stand E")
    }
}
