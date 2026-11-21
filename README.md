# Fantasma

<p align="center">
  <img src="Assets/icon-source.png" width="180" alt="Fantasma icon">
</p>

A macOS terminal with two modes: a **float** — a small, rounded, chrome-less
overlay that summons focused and dismisses on blur — and normal **tiled
windows** your tiling manager treats like any other app. Built on
[libghostty](https://github.com/Lakr233/libghostty-spm) (Ghostty's terminal
engine, packaged for Apple platforms).

<p align="center">
  <img src="docs/screenshots/tiled.png" width="640" alt="A Fantasma tiled window — chrome-less, with a retro Macintosh 128K mock fetch">
</p>

No tabs. No splits. A quick terminal and regular windows, done well.

## Install

One-liner (Apple silicon, downloads the latest release):

```bash
curl -fsSL https://raw.githubusercontent.com/andrew-bierman/fantasma/main/install.sh | sh
```

Homebrew:

```bash
brew tap andrew-bierman/tap
brew install --cask andrew-bierman/tap/fantasma
```

Published builds are currently unnotarized — on first launch, right-click
Fantasma.app → Open, or run
`xattr -dr com.apple.quarantine ~/Applications/Fantasma.app`.

From source:

```bash
git clone https://github.com/andrew-bierman/fantasma && cd fantasma
scripts/install.sh        # build + install to ~/Applications + link the CLI
```

Requires macOS 14+, Swift tools 6.2 (Xcode 26+ toolchain). The first build
downloads a ≈161 MB `GhosttyKit.xcframework`; later builds are cached.

## Usage

**Float** — `fantasma +toggle-float` (or `open -a Fantasma`, or your
configured `hotkey`) summons the overlay focused and typing-ready. Clicking
away, ⌘W, or a second summon hides it. The float remembers its last position
and size across summons and relaunches. With `clear_on_open = true`
(default) every summon starts a fresh shell, and that shell starts in the
working directory of your last Fantasma shell (OSC 7).

**Tiled windows** — `fantasma +new-window` opens a normal titled window that
your tiling manager manages like any other app. ⌘W closes it. Both window
kinds spawn in the last-used directory and switch theme live with system
appearance.

**Find** — ⌘F opens the find bar. Enter / Shift+Enter walk the matches,
Esc closes and refocuses the shell. Powered by the engine's native
scrollback search.

**Fonts** — ⌘= / ⌘- / ⌘0 zoom in, out, and reset, per window.

**Links** — click to open in your browser; only allowlisted schemes
(http, https, mailto) pass, and hovering shows a pointing hand.
`link_url = false` disables opening (links still render).

**CLI** — the binary doubles as a Ghostty-style action CLI:

```bash
fantasma +toggle-float      # summon/dismiss the overlay
fantasma +new-window        # open a tiled window
fantasma +show-config       # print the resolved configuration
fantasma +list-themes       # list bundled theme names
fantasma +reload-config     # re-read the config file
```

**Keys**: ⌘W dismiss/close · ⌘Q quit · ⌘F find · ⌘= / ⌘- / ⌘0 font zoom ·
⌘, opens the config · ⌘-drag moves the float · drag the 8px edges to resize.

## Configuration

`~/.config/fantasma/fantasma.conf` — `key = value` lines, `#` comments,
unknown keys ignored, read at launch. Fantasma also imports recognized keys
from your existing Ghostty config (`~/.config/ghostty/config`): `theme`,
`font-size`, `window-padding-x`, `copy-on-select`, `font-family`. fantasma.conf
values win.

| Key | Default | Meaning |
|-----|---------|---------|
| `theme` | `Dracula` | Theme name; unknown names fall back to the engine default |
| `theme_light` / `theme_dark` | *(unset)* | Per-appearance theme names; unset sides fall back to `theme`. Follows system appearance live |
| `font_size` | `13` | Terminal font size (integer ≥ 1) |
| `font_family` | *(engine default)* | Monospace family name |
| `padding` | `8` | Window padding in points (integer ≥ 0) |
| `clear_on_open` | `true` | `true`: dismissing the float ends its shell; `false`: the shell survives hide/show |
| `copy_on_select` | `true` | Copy selections to the clipboard as you make them |
| `link_url` | `true` | Open clicked links (allowlisted schemes only) |
| `hotkey` | *(off)* | Global summon hotkey, e.g. `cmd+grave` (`cmd`/`ctrl`/`alt`/`shift` + a key). Applied at launch |
| `float_width` / `float_height` | `560` / `360` | Default float size in points (clamped to the screen) |
| `float_x` / `float_y` | *(centered, 110pt from top)* | Default float position in points from the screen's top-left |
| `normal_title_bar` | `true` | `false` hides tiled windows' title bar |

Quoted values (`theme = "Catppuccin Mocha"`) are supported. Changes apply on
relaunch, or run `fantasma +reload-config`. The float's last position and
size persist to
`~/Library/Application Support/Fantasma/state.toml`; explicit `float_*`
config values always win over it.

## yabai

Exempt only the float from tiling, by title (tiled windows stay managed):

```bash
yabai -m rule --add app="^Fantasma$" title="^fantasma-float$" manage=off
```

## Extras

`extras/fantasmasay "boo. terminals should float."` — a friendly ghost says
your words. Self-contained, no dependencies.

## Status

Shipped: float with blur-dismiss and a summon handshake that survives window
manager focus bounce · tiled windows · config file + Ghostty import ·
Ghostty-style CLI · find bar (⌘F) · font zoom · busy-state titles ·
bell → attention · live config reload · light/dark theme pairs ·
cwd-aware spawning · float frame persistence · global hotkey ·
URL allowlist with hover cursor.

Engine-limited in the current libghostty-spm pin: numbered link hints
(no API to enumerate on-screen links), and the theme catalog registry is
empty at runtime — only built-in theme statics resolve (e.g. Dracula);
arbitrary names fall back to the engine default.

## Development

```bash
swift build -c release    # build
swift test                # unit tests
scripts/smoke.sh          # end-to-end AX loop (needs Accessibility permission)
scripts/release.sh        # cut a release from main (bump VERSION first)
scripts/notarize.sh       # optional: Developer ID sign + notarize + staple
```

Every PR that changes code must bump `VERSION` — a GitHub Action enforces it.
Releases are cut only from `main`, and tags are immutable.

Pushing a `v*` tag runs the release workflow: build, tests, then — when the
signing secrets below are configured — Developer ID signing, notarization,
stapling, release asset, and a Homebrew tap checksum update. Without secrets
it publishes unsigned.

| Secret | Meaning |
|--------|---------|
| `APPLE_CERTIFICATE_P12` | Base64 of the Developer ID Application `.p12` export |
| `APPLE_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12` |
| `APPLE_ID` / `APPLE_PASSWORD` / `APPLE_TEAM_ID` | Notary service auth (`APPLE_PASSWORD` is an app-specific password) |
| `TAP_TOKEN` | Optional: PAT with push access to `homebrew-tap`, for automatic cask updates |

## License

GPL-3.0 — see [LICENSE](LICENSE). The libghostty engine it embeds is MIT.
