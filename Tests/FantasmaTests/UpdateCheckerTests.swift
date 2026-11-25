import XCTest
@testable import Fantasma

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparisonUsesNumericComponents() {
        XCTAssertLessThan(FantasmaVersion("0.4.9")!, FantasmaVersion("v0.4.10")!)
        XCTAssertLessThan(FantasmaVersion("0.9.99")!, FantasmaVersion("1.0.0")!)
        XCTAssertEqual(FantasmaVersion("v0.4.11"), FantasmaVersion("0.4.11"))
    }

    func testCheckResultOnlyOffersNewerStableRelease() throws {
        guard case .available(let version, let url) = try UpdateChecker.result(
            currentVersion: "0.4.11", latestTag: "v0.4.12"
        ) else {
            return XCTFail("A newer release should be offered")
        }
        XCTAssertEqual(version.description, "0.4.12")
        XCTAssertEqual(url.absoluteString, "https://github.com/andrew-bierman/fantasma/releases/tag/v0.4.12")

        guard case .current = try UpdateChecker.result(currentVersion: "0.4.11", latestTag: "v0.4.11") else {
            return XCTFail("The installed release should be current")
        }
        guard case .current = try UpdateChecker.result(currentVersion: "0.4.12", latestTag: "v0.4.11") else {
            return XCTFail("A development build should not offer an older release")
        }
    }

    func testMalformedVersionCannotProduceUpdateLink() {
        XCTAssertNil(FantasmaVersion("v0.4"))
        XCTAssertNil(FantasmaVersion("v0.4.11-beta"))
        XCTAssertNil(FantasmaVersion("v0.-1.0"))
        XCTAssertThrowsError(try UpdateChecker.result(currentVersion: "0.4.11", latestTag: "bad"))
    }
}
