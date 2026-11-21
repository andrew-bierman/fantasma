import XCTest
@testable import Fantasma

final class OpenURLGateTests: XCTestCase {
    // MARK: - Allowlisted schemes open

    func testAllowlistedSchemesPass() {
        XCTAssertNotNil(TerminalSurface.openableURL(from: "https://example.com/page?q=1"))
        XCTAssertNotNil(TerminalSurface.openableURL(from: "http://example.com"))
        XCTAssertNotNil(TerminalSurface.openableURL(from: "mailto:someone@example.com"))
    }

    func testSchemeMatchIsCaseInsensitive() {
        XCTAssertNotNil(TerminalSurface.openableURL(from: "HTTPS://EXAMPLE.COM"))
        XCTAssertNotNil(TerminalSurface.openableURL(from: "MailTo:someone@example.com"))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        // The engine hands over scanned text; trailing newline or padding
        // must not disqualify an otherwise clean URL.
        XCTAssertNotNil(TerminalSurface.openableURL(from: "  https://example.com \n"))
    }

    // MARK: - Non-allowlisted schemes are dropped

    func testFileSchemeIsRejected() {
        // Deliberate: NSWorkspace.open on a file URL launches whatever
        // LaunchServices handler claims the file type.
        XCTAssertNil(TerminalSurface.openableURL(from: "file:///tmp/x.sh"))
        XCTAssertNil(TerminalSurface.openableURL(from: "FILE:///etc/passwd"))
    }

    func testArbitrarySchemesAreRejected() {
        XCTAssertNil(TerminalSurface.openableURL(from: "ftp://example.com"))
        XCTAssertNil(TerminalSurface.openableURL(from: "javascript:alert(1)"))
        XCTAssertNil(TerminalSurface.openableURL(from: "ssh://host.example.com"))
        XCTAssertNil(TerminalSurface.openableURL(from: "x-apple-finder://open"))
        XCTAssertNil(TerminalSurface.openableURL(from: "fantasma://toggle"))
    }

    // MARK: - Degenerate allowlisted URLs are dropped

    func testNetworkSchemeRequiresHost() {
        // The engine's text scanner can surface bare-scheme URLs; opening
        // them is pointless and pollutes the browser's history.
        XCTAssertNil(TerminalSurface.openableURL(from: "https://"))
        XCTAssertNil(TerminalSurface.openableURL(from: "http://"))
        XCTAssertNil(TerminalSurface.openableURL(from: "https:///path-only"))
    }

    func testMailtoRequiresAddress() {
        XCTAssertNil(TerminalSurface.openableURL(from: "mailto:"))
        XCTAssertNotNil(TerminalSurface.openableURL(from: "mailto:a@b.com"))
    }

    // MARK: - Malformed input is dropped

    func testMalformedInputIsRejected() {
        XCTAssertNil(TerminalSurface.openableURL(from: ""))
        XCTAssertNil(TerminalSurface.openableURL(from: "not a url"))
        XCTAssertNil(TerminalSurface.openableURL(from: "example.com/no-scheme"))
        // Interior whitespace can never survive URL parsing.
        XCTAssertNil(TerminalSurface.openableURL(from: "https://exa mple.com"))
    }
}
