import Darwin
import XCTest
@testable import Fantasma

final class BusyTitleTests: XCTestCase {
    func testNoForegroundProcessIsIdle() {
        // No process yet (or already torn down): idle, nothing locked.
        let result = BusyTitle.hasRunningCommand(
            foregroundPid: nil,
            foregroundName: nil,
            shellName: "zsh",
            shellPid: nil
        )
        XCTAssertFalse(result.isBusy)
        XCTAssertNil(result.lockedShellPid)
    }

    func testUnidentifiedForegroundMatchingShellNameLocksShellPid() {
        let result = BusyTitle.hasRunningCommand(
            foregroundPid: 4242,
            foregroundName: "zsh",
            shellName: "zsh",
            shellPid: nil
        )
        XCTAssertFalse(result.isBusy)
        XCTAssertEqual(result.lockedShellPid, 4242)
    }

    func testShellWrapperIsIgnoredBeforeTheShellIsObserved() {
        // Fantasma execs the login shell through /bin/sh -c; the wrapper
        // must not surface as a running command (nor lock as the shell).
        let result = BusyTitle.hasRunningCommand(
            foregroundPid: 100,
            foregroundName: "sh",
            shellName: "zsh",
            shellPid: nil
        )
        XCTAssertFalse(result.isBusy)
        XCTAssertNil(result.lockedShellPid)
    }

    func testUnknownForegroundCommandIsBusyWithoutLocking() {
        let result = BusyTitle.hasRunningCommand(
            foregroundPid: 200,
            foregroundName: "vim",
            shellName: "zsh",
            shellPid: nil
        )
        XCTAssertTrue(result.isBusy)
        XCTAssertNil(result.lockedShellPid)
    }

    func testLockedShellPidMakesIdentityWinOverNames() {
        // Same pid as the locked shell: idle even if proc_name returned
        // something else.
        let idle = BusyTitle.hasRunningCommand(
            foregroundPid: 4242,
            foregroundName: "renamed-shell",
            shellName: "zsh",
            shellPid: 4242
        )
        XCTAssertFalse(idle.isBusy)
        XCTAssertEqual(idle.lockedShellPid, 4242)

        // A different foreground is busy and clears the lock; the shell
        // re-locks by name once it is foreground again.
        let busy = BusyTitle.hasRunningCommand(
            foregroundPid: 200,
            foregroundName: "vim",
            shellName: "zsh",
            shellPid: 4242
        )
        XCTAssertTrue(busy.isBusy)
        XCTAssertNil(busy.lockedShellPid)
        let relocked = BusyTitle.hasRunningCommand(
            foregroundPid: 4242,
            foregroundName: "zsh",
            shellName: "zsh",
            shellPid: nil
        )
        XCTAssertFalse(relocked.isBusy)
        XCTAssertEqual(relocked.lockedShellPid, 4242)
    }

    func testDisplayTitle() {
        XCTAssertEqual(BusyTitle.displayTitle(isBusy: true, foregroundName: "vim"), "fantasma — vim")
        XCTAssertEqual(BusyTitle.displayTitle(isBusy: false, foregroundName: "vim"), "fantasma")
        XCTAssertEqual(BusyTitle.displayTitle(isBusy: true, foregroundName: nil), "fantasma")
        XCTAssertEqual(BusyTitle.displayTitle(isBusy: true, foregroundName: ""), "fantasma")
    }

    func testProcessNameAnswersForOwnProcess() {
        // The basename source resolves a live, self-owned pid; exact value
        // depends on the test runner's path, so only presence is asserted.
        let name = BusyTitle.processName(for: getpid())
        XCTAssertNotNil(name)
        XCTAssertFalse(name?.isEmpty ?? true)
    }
}
