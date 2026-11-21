# Fantasma

A macOS overlay terminal that recreates foot's quick-terminal UX: a hotkey
summons a floating, rounded, chrome-less terminal that takes keyboard focus
instantly; clicking away hides it, and the shell inside keeps running.
Summon it again and everything — scrollback, running jobs, working
directory — is still there. It also opens normal, tiled terminal windows
for everyday use.

Built on [libghostty](https://github.com/Lakr233/libghostty-spm)
(Ghostty's terminal engine, packaged for Apple platforms). Fantasma is not
a terminal emulator and not a full terminal app: two window modes, no tabs.

## Build and run

```bash
swift build -c release
scripts/build-app.sh      # assembles Fantasma.app (LSUIElement, no Dock icon)
scripts/install.sh        # installs to ~/Applications and launches
```

The first resolve downloads a ≈161 MB `GhosttyKit.xcframework`; later builds
are quick and cached.

Requires macOS 14+, Swift tools 6.2 (Xcode 26+ toolchain).

## Using it

**Float (quick-launch):** `open -a Fantasma` (or `open /path/to/Fantasma.app`)
shows the overlay, focused and typing-ready. Running the same command again
hides it; once hidden, it shows again — bind that toggle to a hotkey launcher
(Tinycast command: `open -a Fantasma`). Click away or Cmd+W and the overlay
hides. Cmd+Q quits the app.

**Normal windows:** `Fantasma.app/Contents/MacOS/Fantasma --new-window`
(requires Fantasma to be running) opens a normal titled terminal window that
your tiling manager treats like any other app. Cmd+W or the close button
closes that window and ends its shell.

**Window manipulation:** drag the outer 8px edges or corners to resize
(minimum 320×180); hold **Cmd and drag anywhere** to move the overlay.

**Shell lifecycle:** with the default config, dismissing the float ends its
shell — every summon is fresh. Exiting a shell always ends its window
(overlay quit / normal window close).

## Configuration

`~/.config/fantasma/fantasma.conf` — `key = value` lines, `#` comments,
unknown keys ignored, read once at launch:

| Key | Default | Meaning |
|-----|---------|---------|
| `theme` | `Dracula` | Any theme name from the bundled iTerm2 catalog; unknown names fall back to the package default |
| `font_size` | `13` | Terminal font size (integer ≥ 1) |
| `padding` | `8` | Window padding in points (integer ≥ 0) |
| `clear_on_open` | `true` | `true`: dismissing the float ends its shell; `false`: the shell survives hide/show with full scrollback |

Example:

```ini
theme = GruvboxDark
font_size = 14
padding = 12
clear_on_open = false
```

## yabai

Exempt only the float from tiling, by title (normal windows stay tiled):

```bash
yabai -m rule --add app="^Fantasma$" title="^fantasma-float$" manage=off
```

## Tests and smoke

```bash
swift test              # config parser, geometry, window-math unit tests
scripts/smoke.sh        # AX-driven end-to-end float loop (needs Accessibility
                        # permission for the driving terminal)
```

## Name

Provisional. "Fantasma" (ghost) fits the summon-vanish overlay; "moot" was
the runner-up. A rename touches the bundle id constants in
`scripts/build-app.sh`, the app name, and the yabai rule.

## License

MIT — see [LICENSE](LICENSE).
