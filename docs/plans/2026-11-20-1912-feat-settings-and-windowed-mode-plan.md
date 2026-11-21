---
title: "Fantasma settings and windowed mode - Plan"
type: feat
date: 2026-11-20
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Fantasma settings and windowed mode — Plan

## Goal Capsule

- **Objective:** Fantasma becomes tunable and dual-mode: a config file controls theme, font, padding, and whether summoning the float starts fresh or resumes; and a second, normal window mode exists that yabai tiles, so Fantasma covers both the quick-launch float and an everyday tiled terminal without tabs.
- **Means:** A hand-parsed config file read at launch (KTD13) feeding surface creation and show/hide behavior (KTD14); mode separation by window title with a DistributedNotificationCenter shim for the windowed mode (KTD15, KTD16).
- **Authority:** R-IDs own behavior; KTDs own mechanism; the v1 plan's KTDs keep governing the overlay core this extends.
- **Stop conditions:** If the exec backend cannot spawn a second concurrent surface in one process, stop and report.
- **Execution profile:** Red-first parser tests for the config layer; live AX loop for mode behavior.
- **Finishing:** `ce-work` implements and verifies; Andrew reviews and merges; the dotfiles wiring PR (U5 scope) lands as its own separate PR after.

---

## Product Contract

### Summary

`~/.config/fantasma/fantasma.conf` tunes Fantasma (theme, font size, padding, clear-on-open). The float keeps its summon-dismiss flow; `clear_on_open = true` (the default) starts a fresh shell each summon, `false` keeps v1's persistent shell. A second trigger opens a normal titled terminal window that yabai tiles like any app.

### Problem Frame

v1 shipped one fixed behavior: persistent shell, Dracula, fixed geometry — and no everyday-window mode. The maintainer wants cleared-by-default with a keep option for others, wants both foot modes (float + tiled client), and distribution needs knobs people can tweak without recompiling. A config file matches terminal culture (foot.ini, ghostty config) and the app's no-UI constraint (LSUIElement: no menu bar, no Dock).

### Requirements

**Config**

- R16. Fantasma reads `~/.config/fantasma/fantasma.conf` at launch: `key = value` lines, `#` comments, unknown keys ignored. Keys: `theme` (theme-catalog name, default `Dracula`), `font_size` (default `13`), `padding` (default `8`), `clear_on_open` (`true`/`false`, default `true`).
- R20. Every key and its default is documented in the README.

**Float behavior**

- R17. With `clear_on_open = true`, dismissing the float ends its shell and the next summon starts a fresh one; with `false`, dismissing keeps the shell exactly as v1 did (hide/show restores the session).

**Modes**

- R18. The overlay window carries the yabai/AX-visible title `fantasma-float` even though it renders borderless.
- R19. Invoking the binary with `--new-window` while Fantasma runs opens one normal titled window (title `fantasma`, traffic lights, standard window level, resizable, yabai tiles it) hosting its own login shell; Cmd+W closes that window and ends its shell. The overlay and normal windows coexist independently.

### Key Decisions

- KD5. Settings live in a config file, not a UI. Governs R16, R20. (session-settled: user-directed — chosen over a settings window: the app is LSUIElement with no menu bar or Dock icon, and file-based config is the terminal-app convention.)
- KD6. `clear_on_open` defaults to `true`. Governs R17. (session-settled: user-directed — chosen over persistent-by-default: "i want cleared but could see some wanting opened".)
- KD7. Both foot modes exist — float + normal tiled window — with no tabs, ever. Governs R18, R19. (session-settled: user-directed — chosen over float-only and over tabbed multiplexing.)

### Success Criteria

- SC4. Editing `clear_on_open` and relaunching changes summon behavior as R17 describes.
- SC5. Overlay float is exempt from tiling while a normal Fantasma window is tiled by yabai at the same time.

### Acceptance Examples

- AE4. Covers R16, R17 — **Given** `clear_on_open = false`, **When** the user runs a command, dismisses, and re-summons, **Then** the output is still there; with the key `true`, the same flow shows a fresh prompt.
- AE5. Covers R19 — **Given** Fantasma is running, **When** the binary is invoked with `--new-window`, **Then** a titled window appears that yabai tiles, with its own independent shell.

### Scope Boundaries

Outside this product's identity: tabs, splits, a settings GUI, live config reload (restart to apply), per-window config. Deferred to Follow-Up Work: the dotfiles wiring PR (title-based yabai rule `app="^Fantasma$" title="^fantasma-float$" manage=off` replacing the app-wide rule, Tinycast command docs, regression tests) — a separate PR in andrew-bierman/dotfiles after this lands.

Open Questions: none blocking.

---

## Planning Contract

### Key Technical Decisions

- KTD13. Config is a flat `key = value` file parsed by a small hand-written reader (~40 lines) — no TOML/INI dependency for four keys; read once at launch (restart to apply is documented, not a watcher). Governs R16, R20.
- KTD14. `clear_on_open = true` implements dismissal as surface teardown (controller released, PTY ends) at hide time, with `show()` creating a fresh surface; `false` keeps the v1 orderOut-only path. The overlay never blocks on teardown. Governs R17.
- KTD15. Modes are distinguished by window title — the overlay sets `fantasma-float` (invisible in a borderless window but present to AX/yabai), normal windows use `fantasma` — so yabai rules can exempt the float by title while tiling everything else, the same pattern the foot-float integration used. Governs R18, R19.
- KTD16. The windowed-mode trigger is a DistributedNotificationCenter broadcast: the binary invoked with `--new-window` posts `com.andrewbierman.fantasma.new-window` and exits; the running instance observes it and opens a normal window. Chosen over `open --args` (ignored for running apps) and over URL schemes (plist work for one trigger). Governs R19.
- KTD17. Normal windows are plain titled `NSWindow`s (standard level, no floating, no all-spaces collection behaviors) hosting their own `TerminalSurface`; overlay-specific behaviors (pin, auto-hide, edge resizer) do not apply to them. Governs R19.

### Assumptions

Un-validated agent bets, recorded because this run proceeds without a scoping confirmation:

- Multiple normal windows may coexist; each is independent (no shared-shell semantics).
- The config file is optional; absent file or absent key → documented defaults.
- `font_size` and `padding` accept integers; invalid values fall back to defaults silently.
- The overlay title change does not affect Tinycast (`open -a` targets the app, not the title).

### Risks and Dependencies

- A titled overlay window title could confuse yabai rules that match `app` only — mitigated by the title-based rule in the deferred dotfiles PR; until it lands, the current session-scoped rule applies.
- `DistributedNotificationCenter` delivery is asynchronous; the shim tolerates the running instance not existing (notification posts to nothing).

### Sources and Research

- libghostty-spm 3.0.1 checkout (resolved API: `TerminalController(configSource:theme:terminalConfiguration:)`, `TerminalSurfaceOptions(backend:workingDirectory:envVars:command:)`, delegates) — read directly this session.
- justty (`0x96f/justty`) `TerminalSession.swift` — surface-per-window pattern already ported in v1.
- foot's two-mode model (client vs `foot float`) — the product shape KD7 names.
- v1 plan KTDs 1–12 and this session's prototype findings (referenced, not restated).

---

## Implementation Units

### U1. Config layer

- **Goal:** Fantasma reads and applies a config file.
- **Requirements:** R16.
- **Dependencies:** none.
- **Files:** `Sources/Fantasma/FantasmaConfig.swift` (new), `Tests/FantasmaTests/FantasmaConfigTests.swift` (new), `Package.swift` (test target exists).
- **Approach:** Hand-written reader (KTD13): trim, skip blanks and `#` comments, split on first `=`, known keys collected, unknown ignored, invalid values fall back to defaults. Struct exposes resolved values with defaults; lookup path `~/.config/fantasma/fantasma.conf` overridable for tests.
- **Execution note:** Red-first — write the parser tests before the implementation and observe the failure.
- **Test scenarios:**
  - Happy path: full file parses all four keys to expected values.
  - Edge case: missing file returns all defaults.
  - Edge case: unknown keys, blank lines, `#` comments, extra whitespace, and `true`/`false` casing are handled; invalid `font_size`/`padding` fall back to defaults.
- **Verification:** `swift test` green including the new parser cases.

### U2. Config applied to behavior

- **Goal:** Theme, font, padding, and clear-on-open actually change the app.
- **Requirements:** R17.
- **Dependencies:** U1.
- **Files:** `Sources/Fantasma/TerminalSurface.swift`, `Sources/Fantasma/AppDelegate.swift`.
- **Approach:** `TerminalSurface` takes resolved config (theme name → catalog lookup, font size and padding into the builder); hide path consults `clear_on_open`: teardown (KTD14) vs orderOut; show path creates a fresh surface when the previous one was torn down. Overlay window title set to `fantasma-float` (R18, KTD15).
- **Test scenarios:**
  - Covers AE4. With `false`: run command, dismiss (focus loss), re-summon — output intact.
  - With `true`: dismiss tears the surface down (shell process gone), re-summon shows a fresh prompt.
- **Verification:** both variants exercised live via the AX loop; `swift test` still green.

### U3. Normal window mode

- **Goal:** `--new-window` opens a tiled, titled terminal window beside the float.
- **Requirements:** R19.
- **Dependencies:** U2.
- **Files:** `Sources/Fantasma/AppDelegate.swift`, `Sources/Fantasma/NormalWindowController.swift` (new), `Sources/Fantasma/main.swift` (shim branch).
- **Approach:** KTD16 shim (post notification, exit when not the resident instance); KTD17 window (titled, standard level, own `TerminalSurface`, rounded corners not applied); Cmd+W closes the window and tears its surface down; overlay float and normal windows coexist. Shell exit in a normal window closes that window only.
- **Test scenarios:**
  - Covers AE5. Invoke `--new-window` while running: titled window appears, independent shell (command in one does not affect the other).
  - Edge case: shim invoked with no running instance — exits quietly (or launches the app, per implementation, documented).
  - Edge case: Cmd+W on the normal window closes it and ends only its shell; the float is unaffected.
- **Verification:** live AX loop — both windows present simultaneously, distinct processes' shells verified by marker files.
- **Execution note:** smoke-first on the live desktop; unit coverage not practical for window choreography.

### U4. Docs and README

- **Goal:** A stranger can configure and use both modes from the README.
- **Requirements:** R20.
- **Dependencies:** U1–U3.
- **Files:** `README.md`.
- **Approach:** Config keys table with defaults, both mode triggers, yabai rule snippet updated to the title-based form.
- **Test scenarios:** Test expectation: none — documentation.
- **Verification:** README matches implemented keys and commands exactly.

### U5. Dotfiles wiring PR (separate repository)

- **Goal:** Persistent yabai exemption for the float and Tinycast docs.
- **Requirements:** none in this repo.
- **Dependencies:** U3 merged.
- **Files:** in andrew-bierman/dotfiles: `yabai/yabairc`, `README.md`, `tests/test_foot.py`.
- **Approach:** Replace `app="^Fantasma$" manage=off` with `app="^Fantasma$" title="^fantasma-float$" manage=off`; document both Tinycast commands; update the regression tests. Lands as its own squash-merged PR per that repo's rules.
- **Test scenarios:** Test expectation: none — covered by the dotfiles repo's own test suite.
- **Verification:** dotfiles tests green; PR open and merged.

---

## Verification Contract

| Check | Command | Proves |
|---|---|---|
| Build | `swift build -c release` | Compiles |
| Unit tests | `swift test` | Config parser (red-first), geometry, resize |
| Bundle | `scripts/build-app.sh` | Launchable app |
| Smoke | `scripts/smoke.sh` | AE1–AE3 regression |
| Mode loop | live AX script | AE4–AE5: config variants, both modes, independence |
| Manual | live desktop | SC4–SC5 |

---

## Definition of Done

- Global: every Verification row green; `clear_on_open` flips behavior as R17; normal window tiles while the float floats (SC5); no leftover Fantasma processes after testing; dead approaches removed from the diff.
- Per unit: each unit's Verification satisfied before dependents start; config tests exist and are green before U2 begins.
