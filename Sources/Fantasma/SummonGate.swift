// Pure decision logic for the float's summon handshake. Unit-tested; the
// app delegate owns the timers and AppKit calls.

/// Tracks a summon from request until the float is "armed" for
/// hide-on-focus-loss. Replaces the old fixed 0.3 s latch, which expired
/// whether or not activation ever succeeded: window-manager focus bounce
/// arriving after the latch hid the float instantly ("flashes and
/// vanishes"), and a failed activation left a visible window with dead
/// input. The gate keeps the float up and retries activation until focus
/// has been held for a full hold interval; only then does a focus loss
/// dismiss.
struct SummonGate {
    enum ActivationDecision: Equatable {
        case focused   // we hold key + active: start the arm hold
        case retry     // not yet: schedule another activation attempt
        case gaveUp    // retries exhausted: stay visible, unarmed
    }

    enum FocusLossDecision: Equatable {
        case hide      // armed and lost focus: dismiss
        case reattempt // lost focus mid-summon: re-activate, stay visible
        case ignore    // already dismissed: nothing to do
    }

    /// Retry attempts allowed after the initial activation check.
    let maxAttempts: Int

    private(set) var attemptsLeft = 0
    private(set) var holdingFocus = false
    private(set) var armed = false
    private(set) var dismissed = false

    init(maxAttempts: Int = 6) {
        self.maxAttempts = maxAttempts
    }

    mutating func showRequested() {
        attemptsLeft = maxAttempts
        holdingFocus = false
        armed = false
        dismissed = false
    }

    /// The float is going away (hide or teardown); stray resign-key
    /// notifications from orderOut must not resurrect it.
    mutating func hid() {
        holdingFocus = false
        armed = false
        dismissed = true
    }

    /// Called right after NSApp.activate + makeKeyAndOrderFront.
    mutating func activationCheck(isActive: Bool, isKey: Bool) -> ActivationDecision {
        guard !dismissed else { return .gaveUp }
        if isActive && isKey {
            holdingFocus = true
            return .focused
        }
        guard attemptsLeft > 0 else { return .gaveUp }
        attemptsLeft -= 1
        return .retry
    }

    /// Arm-hold timer fired. Returns true when focus was held for the whole
    /// hold and the gate is now armed; false means focus slipped mid-hold
    /// and the caller should re-attempt activation.
    mutating func holdElapsed(isActive: Bool, isKey: Bool) -> Bool {
        guard holdingFocus, !dismissed else { return false }
        holdingFocus = false
        guard isActive && isKey else { return false }
        armed = true
        return true
    }

    mutating func focusLost() -> FocusLossDecision {
        if dismissed { return .ignore }
        guard armed else { return .reattempt }
        armed = false
        return .hide
    }
}
