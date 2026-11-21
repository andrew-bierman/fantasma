import XCTest
@testable import Fantasma

final class SummonGateTests: XCTestCase {
    func testHappyPathArmsThenHides() {
        var gate = SummonGate()
        gate.showRequested()
        XCTAssertEqual(gate.activationCheck(isActive: true, isKey: true), .focused)
        XCTAssertTrue(gate.holdElapsed(isActive: true, isKey: true))
        XCTAssertEqual(gate.focusLost(), .hide)
    }

    /// The reported bug: WM focus bounce steals focus before the hold
    /// completes — the float must re-attempt, not vanish.
    func testFocusBounceDuringHoldReattemptsInsteadOfHiding() {
        var gate = SummonGate()
        gate.showRequested()
        XCTAssertEqual(gate.activationCheck(isActive: true, isKey: true), .focused)
        XCTAssertFalse(gate.holdElapsed(isActive: false, isKey: false))
        XCTAssertEqual(gate.focusLost(), .reattempt)
        // Fight back and win.
        XCTAssertEqual(gate.activationCheck(isActive: true, isKey: true), .focused)
        XCTAssertTrue(gate.holdElapsed(isActive: true, isKey: true))
        XCTAssertEqual(gate.focusLost(), .hide)
    }

    /// Activation never succeeds (fresh launch, LS never activates):
    /// bounded retries, then stay visible and unarmed — never auto-hide.
    func testActivationRetriesThenGivesUp() {
        var gate = SummonGate()
        gate.showRequested()
        for _ in 0..<gate.maxAttempts {
            XCTAssertEqual(gate.activationCheck(isActive: false, isKey: false), .retry)
        }
        XCTAssertEqual(gate.activationCheck(isActive: false, isKey: false), .gaveUp)
        XCTAssertEqual(gate.focusLost(), .reattempt)
    }

    func testShowRequestedRearmsAfterGiveUp() {
        var gate = SummonGate()
        gate.showRequested()
        for _ in 0..<gate.maxAttempts { _ = gate.activationCheck(isActive: false, isKey: false) }
        XCTAssertEqual(gate.activationCheck(isActive: false, isKey: false), .gaveUp)
        gate.showRequested()
        XCTAssertEqual(gate.activationCheck(isActive: false, isKey: false), .retry)
    }

    /// hide() → orderOut fires didResignKey: a dismissed gate must neither
    /// hide again nor resurrect the window.
    func testDismissedGateIgnoresStrayFocusLoss() {
        var gate = SummonGate()
        gate.showRequested()
        XCTAssertEqual(gate.activationCheck(isActive: true, isKey: true), .focused)
        XCTAssertTrue(gate.holdElapsed(isActive: true, isKey: true))
        gate.hid()
        XCTAssertEqual(gate.focusLost(), .ignore)
        XCTAssertEqual(gate.activationCheck(isActive: true, isKey: true), .gaveUp)
    }

    func testHoldRequiresPriorFocus() {
        var gate = SummonGate()
        gate.showRequested()
        // Hold fired without a focused activation check: not armed.
        XCTAssertFalse(gate.holdElapsed(isActive: true, isKey: true))
        XCTAssertEqual(gate.focusLost(), .reattempt)
    }
}
