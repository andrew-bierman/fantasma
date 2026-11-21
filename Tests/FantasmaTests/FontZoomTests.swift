import XCTest
@testable import Fantasma

final class FontZoomTests: XCTestCase {
    func testZoomKeyCharactersMapToDirections() {
        XCTAssertEqual(FontZoom.Direction(matching: "="), .increase)
        XCTAssertEqual(FontZoom.Direction(matching: "+"), .increase)
        XCTAssertEqual(FontZoom.Direction(matching: "-"), .decrease)
        XCTAssertEqual(FontZoom.Direction(matching: "0"), .reset)
    }

    func testOtherKeysDoNotMap() {
        XCTAssertNil(FontZoom.Direction(matching: "w"))
        XCTAssertNil(FontZoom.Direction(matching: "q"))
        XCTAssertNil(FontZoom.Direction(matching: "_"))
        XCTAssertNil(FontZoom.Direction(matching: ""))
        XCTAssertNil(FontZoom.Direction(matching: nil))
    }
}
