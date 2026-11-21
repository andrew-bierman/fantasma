import XCTest
@testable import Fantasma

final class FindBarTests: XCTestCase {
    func testSearchActionPrefixesNeedle() {
        XCTAssertEqual(FindBarController.Action.search(needle: "error"), "search:error")
    }

    func testSearchActionKeepsNeedleVerbatim() {
        // The engine splits an action at the first colon only: spaces,
        // further colons and unicode reach the needle untouched.
        XCTAssertEqual(FindBarController.Action.search(needle: "a:b c:d"), "search:a:b c:d")
        XCTAssertEqual(FindBarController.Action.search(needle: "foo bar"), "search:foo bar")
        XCTAssertEqual(FindBarController.Action.search(needle: "∃x"), "search:∃x")
    }

    func testEmptyNeedleIsTheEngineCancelPath() {
        // Zero-length needle stops the engine's search thread.
        XCTAssertEqual(FindBarController.Action.search(needle: ""), "search:")
    }

    func testNavigateActions() {
        XCTAssertEqual(FindBarController.Action.navigate(.next), "navigate_search:next")
        XCTAssertEqual(FindBarController.Action.navigate(.previous), "navigate_search:previous")
    }

    func testDirectionRawValuesAreEngineParameters() {
        // The raw values are the engine's `NavigateSearch` enum cases.
        XCTAssertEqual(FindBarController.Direction.next.rawValue, "next")
        XCTAssertEqual(FindBarController.Direction.previous.rawValue, "previous")
    }

    func testEndSearchAction() {
        XCTAssertEqual(FindBarController.Action.endSearch, "end_search")
    }
}
