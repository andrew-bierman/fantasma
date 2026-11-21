# Fantasma

A macOS overlay terminal that recreates foot's quick-terminal UX: a hotkey
summons a floating, rounded, chrome-less terminal that takes keyboard focus
instantly; clicking away hides it, and the shell inside keeps running.
Summon it again and everything — scrollback, running jobs, working
directory — is still there.

Built on [libghostty](https://github.com/Lakr233/libghostty-spm)
(Ghostty's terminal engine, packaged for Apple platforms). Fantasma is not
a terminal emulator and not a full terminal app: it is one summon-and-dismiss
overlay surface, nothing more.

## Build and run

```bash
swift build -c release
scripts/build-app.sh      # assembles Fantasma.app (LSUIElement, no Dock icon)
open Fantasma.app
```

The first resolve downloads a ≈161 MB `GhosttyKit.xcframework`; later builds
are quick and cached.

Requires macOS 14+, Swift tools 6.2 (Xcode 26+ toolchain).

## Using it

- `open -a Fantasma` (or `open /path/to/Fantasma.app`) shows the overlay,
  focused and typing-ready.
- Running the same command again hides it; once hidden, it shows again.
  This toggle is what you bind to a hotkey launcher (Tinycast command:
  `open -a Fantasma` once the app is installed; use the bundle path before that).
- Click away or press Cmd+W and the overlay hides — the shell keeps running.
- Cmd+Q quits the app and the shell. Exiting the shell also quits the app.
- Drag the edges or corners to resize (minimum 320×180).

## yabai

Add the app to your yabai ignore rules so it never enters the tiling layout:

```bash
yabai -m rule --add app="^Fantasma$" manage=off
```

## Tests and smoke

```bash
swift test              # geometry and window-math unit tests
scripts/smoke.sh        # AX-driven end-to-end loop (needs Accessibility
                        # permission for the driving terminal)
```

## Name

Provisional. "Fantasma" (ghost) fits the summon-vanish overlay; "moot" was
the runner-up. A rename touches the bundle id constants in
`scripts/build-app.sh`, the app name, and the yabai rule.

## License

MIT — see [LICENSE](LICENSE).
