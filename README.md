# Fantasma

<p align="center">
  <img src="Assets/icon-source.png" width="180" alt="Fantasma icon">
</p>

A macOS terminal with two modes: a **float** — a small, rounded, chrome-less
overlay that summons with a hotkey, takes focus instantly, and dismisses on
blur — and normal **tiled windows** your tiling manager treats like any other
app. Built on [libghostty](https://github.com/Lakr233/libghostty-spm)
(Ghostty's terminal engine, packaged for Apple platforms).

<p align="center">
  <img src="docs/screenshots/float.png" width="560" alt="The fantasma float">
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

The build is unnotarized — on first launch, right-click Fantasma.app → Open,
or run `xattr -dr com.apple.quarantine ~/Applications/Fantasma.app`.

From source:

```bash
git clone https://github.com/andrew-bierman/fantasma && cd fantasma
scripts/install.sh        # build + install to ~/Applications + link the CLI
```

Requires macOS 14+, Swift tools 6.2 (Xcode 26+ toolchain). The first build
downloads a ≈161 MB `GhosttyKit.xcframework`; later builds are cached.

## Usage

**Float** — `fantasma +toggle-float` (or `open -a Fantasma`) summons the
overlay focused and typing-ready. Running the same command again hides it.
Clicking away or Cmd+W hides it. With the default config, dismissing ends the
shell and every summon is fresh; set `clear_on_open = false` to keep the
shell across hide/show.

**Tiled windows** — `fantasma +new-window` opens a normal titled window that
your tiling manager manages like any other app. Cmd+W closes it.

**CLI** — the binary doubles as a Ghostty-style action CLI:

```bash
fantasma +toggle-float      # summon/dismiss the overlay
fantasma +new-window        # open a tiled window
fantasma +show-config       # print the resolved configuration
fantasma +list-themes       # list bundled theme names
fantasma +reload-config     # re-read the config file
```

**Keys**: Cmd+W dismisses (float) or closes (tiled) · Cmd+Q quits ·
Cmd+drag moves the float · drag the 8px edges to resize · ⌘, opens the
config.

## Configuration

`~/.config/fantasma/fantasma.conf` — `key = value` lines, `#` comments,
unknown keys ignored, read at launch. Fantasma also imports recognized keys
from your existing Ghostty config (`~/.config/ghostty/config`): `theme`,
`font-size`, `window-padding-x`, `copy-on-select`, `font-family`. fantasma.conf
values win.

| Key | Default | Meaning |
|-----|---------|---------|
| `theme` | `Dracula` | Theme name; unknown names fall back to the engine default |
| `font_size` | `13` | Terminal font size (integer ≥ 1) |
| `font_family` | *(engine default)* | Monospace family name |
| `padding` | `8` | Window padding in points (integer ≥ 0) |
| `clear_on_open` | `true` | `true`: dismissing the float ends its shell; `false`: the shell survives hide/show |
| `copy_on_select` | `true` | Copy selections to the clipboard as you make them |
| `float_width` / `float_height` | `720` / `480` | Float size in points (clamped to the screen) |
| `float_x` / `float_y` | *(centered, 110pt from top)* | Float position in points from the screen's top-left |
| `normal_title_bar` | `true` | `false` hides tiled windows' title bar |

Quoted values (`theme = "Catppuccin Mocha"`) are supported. Changes apply on
relaunch, or run `fantasma +reload-config`.

## yabai

Exempt only the float from tiling, by title (tiled windows stay managed):

```bash
yabai -m rule --add app="^Fantasma$" title="^fantasma-float$" manage=off
```

## Extras

`extras/fantasmasay "boo. terminals should float."` — the mascot ghost says
your words (ASCII generated from the app icon; requires `cowsay`).

## Development

```bash
swift build -c release    # build
swift test                # unit tests
scripts/smoke.sh          # end-to-end AX loop (needs Accessibility permission)
scripts/release.sh        # cut a release from main (bump VERSION first)
```

Every PR that changes code must bump `VERSION` — a GitHub Action enforces it.
Releases are cut only from `main`, and tags are immutable.

## License

MIT — see [LICENSE](LICENSE).
