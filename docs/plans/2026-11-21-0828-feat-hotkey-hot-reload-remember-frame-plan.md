---
title: "Hotkey Hot-Reload and remember_frame Opt-Out - Plan"
type: feat
date: 2026-11-21
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Hotkey Hot-Reload and remember_frame Opt-Out - Plan

## Goal Capsule

- **Objective:** After a user edits `fantasma.conf` and runs `fantasma +reload-config`, the global hotkey binding is active immediately (old combo released, new combo live, no app restart), and the float places itself from config/defaults whenever `remember_frame = false`.
- **Means:** Re-register through the existing Carbon unregister/register pair driven by `HotkeyParser`, and gate `FloatFrameState` load/store on a new `remember_frame` config key (KTD1, KTD2).
- **Authority hierarchy:** Product behavior lives on R1–R6; implementation mechanism on KTD1–KTD2; units carry only local deltas.
- **Stop conditions:** A Carbon API constraint that makes live re-registration infeasible, or evidence the reload path cannot observe config changes it already observes today — report and stop, do not fake.
- **Execution profile:** Local Swift package, `swift build` + `swift test`, manual reload verification per the Verification Contract.
- **Finisher:** `ce-work` implements and verifies; the user merges the PR.

## Product Contract

### Summary

Two roadmap leftovers from the 0.4.x fleet run: the global hotkey currently registers only at launch, so changing `hotkey` in the config requires restarting Fantasma; and the float always persists and restores its frame, with no opt-out. This plan makes the hotkey binding live-reloadable and adds `remember_frame` as an opt-out for frame persistence.

### Problem Frame

The hotkey deferral was named when the hotkey unit shipped (registration at launch only). Frame persistence shipped without an opt-out, so a user who prefers fixed placement cannot have one. Both are config-file-only product behaviors — no UI, matching the project rule.

### Requirements

- R1. Changing `hotkey` through the config-reload path unbinds the previous global hotkey and binds the new value live, without an app restart.
- R2. Reloading to an empty or invalid `hotkey` disables the global hotkey live, with the same warning semantics the launch path uses.
- R3. A config reload that does not change `hotkey` performs no hotkey unregister/register work.
- R4. With `remember_frame = false`, the float ignores the frame-state file on launch and skips writing it on hide, resize, and quit; the file on disk is left untouched.
- R5. `remember_frame` defaults to `true`, so existing installs keep current behavior.
- R6. `fantasma +show-config` prints `remember_frame`.

### Scope Boundaries

- Per-screen frame recall and normal-window frame persistence stay deferred (separate follow-up).
- Numbered link hints and the theme-catalog registry remain upstream-blocked (engine-limited); this plan does not touch them.
- The state file is not deleted when persistence is off (R4 says "left untouched").

## Planning Contract

- KTD1. Hotkey reload re-uses the launch path: `unregisterGlobalHotkey()` then `registerGlobalHotkey()`, which re-parses `config.hotkey` through `HotkeyParser` — invalid or empty values land in the existing disabled-with-warning case, so R2 falls out of the launch semantics for free. Carbon offers no update call; unregister/register is the API shape, and re-parse keeps one parsing authority. A pure `changed(previous:current:)` check on the raw strings gates the work so R3 holds.
- KTD2. `remember_frame = false` skips both `FloatFrameState.load` (launch placement) and `FloatFrameState.store` (hide/resize/quit); the state file is left as-is on disk. Config `float_width/height/x/y` remain the authoritative placement when state is skipped.

### Assumptions

- An existing `state.toml` is left in place when persistence is off — not deleted (easier to re-enable without losing a remembered frame).
- The hotkey binds the float toggle only; no per-window or multi-action hotkeys are in scope.
- Config stays file-only; no settings UI (standing project rule).

## Implementation Units

### U1. `remember_frame` config key and persistence gate

- **Goal:** Users can turn float frame persistence off with one config line (R4, R5, R6).
- **Dependencies:** none
- **Files:** `Sources/Fantasma/FantasmaConfig.swift`, `Sources/Fantasma/AppDelegate.swift`, `Sources/Fantasma/FantasmaCLI.swift`, `Tests/FantasmaTests/FantasmaConfigTests.swift`
- **Approach:**
  1. Add `var rememberFrame = true` to `FantasmaConfig` with a `remember_frame` parse case following the existing `hotkey` pattern.
  2. Gate the `FloatFrameState.load` call in the launch placement path and the `FloatFrameState.store` call in the persistence path on `config.rememberFrame` (KTD2).
  3. Add the `remember_frame` line to `+show-config`.
- **Patterns to follow:** The `hotkey` parse case and its `+show-config` line (same file, same style).
- **Test scenarios:**
  - Config with no `remember_frame` line parses to `rememberFrame == true` (R5).
  - `remember_frame = false` parses to `rememberFrame == false` (R4).
  - Quoted `remember_frame = "false"` parses to `false`, matching the quoted-values rule.
- **Verification:** `swift test` green; manual: set `false`, drag the float, relaunch — float appears at config/default placement and `state.toml` mtime is unchanged.

### U2. Hotkey hot-reload on config reload

- **Goal:** Editing `hotkey` takes effect on `+reload-config` without a restart (R1, R2, R3).
- **Dependencies:** none
- **Files:** `Sources/Fantasma/AppDelegate.swift`, `Sources/Fantasma/HotkeyConfig.swift`, `Tests/FantasmaTests/HotkeyConfigTests.swift`
- **Approach:**
  1. Add a pure decision helper (in `HotkeyConfig.swift`, alongside the parser) `changed(previous:current:) -> Bool` on raw binding strings; equal strings — including two empties — mean no change (R3).
  2. In `reloadConfigRequested`, when the helper reports a change: `unregisterGlobalHotkey()` then `registerGlobalHotkey()`. The register path already parses `config.hotkey` — empty/invalid lands disabled-with-warning, which is R2.
  3. Place the rebind block immediately after the config equality guard at the top of `reloadConfigRequested`, before the `clear_on_open` and `surfaceChanged` early returns — only the `changed` check may gate it, so R1 holds when `clear_on_open = false`.
  4. Log the rebind via `fantasmaLog` so the change is observable.
- **Patterns to follow:** The existing `registerGlobalHotkey()` / `unregisterGlobalHotkey()` pair; the parse-warning style in `HotkeyParser`.
- **Test scenarios:**
  - `changed("", "")` is `false` (R3, no-op case).
  - `changed("cmd+grave", "cmd+grave")` is `false` (R3).
  - `changed("", "cmd+grave")` is `true` (R1).
  - `changed("cmd+grave", "")` is `true` (R2).
  - `changed("cmd+grave", "ctrl+space")` is `true` (R1).
- **Verification:** `swift test` green; manual per the Verification Contract.

### U3. README config documentation

- **Goal:** The new key and the reload behavior are documented for users (R4, R6).
- **Dependencies:** U1
- **Files:** `README.md`
- **Approach:** Add `remember_frame` to the Configuration table; extend the hotkey row's meaning with "re-registers live on +reload-config".
- **Test expectation:** none — documentation only.
- **Verification:** Table renders correctly on GitHub.

## Verification Contract

| Gate | Command | Passes when |
|---|---|---|
| Build | `swift build` | exits clean |
| Unit tests | `swift test` | all green, including new parser and reload-decision tests |
| Manual reload | edit `hotkey` in `~/.config/fantasma/fantasma.conf`, run `fantasma +reload-config` | old combo free, new combo summons; `fantasma.log` shows the rebind |
| Manual reload (clear_on_open off) | set `clear_on_open = false`, edit `hotkey`, run `fantasma +reload-config` | new combo still summons without restart |
| Manual persistence off | set `remember_frame = false`, `+reload-config`, move float, relaunch | float at config/default placement; `state.toml` untouched |
| Manual show-config | `fantasma +show-config` | prints `remember_frame` and `hotkey` |

## Definition of Done

- U1–U3 complete with the test scenarios above passing and 94+ existing tests still green.
- No dead code: the old launch-only registration path is subsumed, not duplicated.
- README documents both behaviors; `+show-config` reflects the live config.
- Work lands as a merged PR per the repo's hook-enforced flow with a `VERSION` bump.
