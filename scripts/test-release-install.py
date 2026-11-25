"""Exercise the release installer offline with a synthetic app ZIP."""

import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def snapshot(bundle):
    entries = {}
    for path in sorted(bundle.rglob("*")):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            contents = os.readlink(path)
        elif stat.S_ISREG(mode):
            contents = path.read_bytes()
        else:
            contents = None
        entries[str(path.relative_to(bundle))] = (mode, contents)
    return entries


def test_release_install(installer):
    # Avoid the system temporary directory even when run outside CI.
    scratch = Path(os.environ.get("TMPDIR") or Path.home() / ".cache" / "fantasma")
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-install-", dir=scratch) as directory:
        root = Path(directory).resolve()
        app = root / "Fantasma-0.0.0-arm64" / "Fantasma.app"
        signature = app / "Contents/Resources/GhosttyKit_GhosttyTerminal.bundle/_CodeSignature/CodeResources"
        signature.parent.mkdir(parents=True)
        signature.write_bytes(b"synthetic nested signature\n")
        signature.chmod(0o640)
        executable = app / "Contents/MacOS/Fantasma"
        executable.parent.mkdir()
        executable.write_bytes(b"synthetic executable\n")
        executable.chmod(0o751)
        (executable.parent / "Fantasma-link").symlink_to("Fantasma")
        (app / "Contents/Resources/MacOS-link").symlink_to("../MacOS")
        archive = root / "release.zip"
        subprocess.run(
            ["zip", "-qyr", str(archive), app.parent.name], cwd=root, check=True
        )

        stubs = root / "bin"
        stubs.mkdir()
        for name, body in {
            "uname": 'if [ "$#" -eq 0 ]; then echo Darwin; else echo arm64; fi',
            "python3": 'echo "https://offline.invalid/Fantasma.zip"',
            "curl": 'cp "$TEST_ARCHIVE" "$4"',
            "open": 'printf "%s\\n" "$@" > "$TEST_LAUNCH"',
            "xattr": 'printf "%s\\n" "$@" > "$TEST_XATTR"',
        }.items():
            stub = stubs / name
            stub.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
            stub.chmod(0o755)

        home = root / "home"
        installed = home / "Applications/Fantasma.app"
        installed.mkdir(parents=True)
        (installed / "old-install").touch()
        launch = root / "launch"
        xattr = root / "xattr"
        subprocess.run(
            ["bash", str(installer)],
            check=True,
            env={
                **os.environ,
                "HOME": str(home),
                "PATH": f"{stubs}:{os.environ['PATH']}",
                "TMPDIR": str(root),
                "TEST_ARCHIVE": str(archive),
                "TEST_LAUNCH": str(launch),
                "TEST_XATTR": str(xattr),
            },
        )

        expected = snapshot(app)
        actual = snapshot(installed)
        changed = sorted(
            entry for entry in expected.keys() | actual.keys()
            if expected.get(entry) != actual.get(entry)
        )
        assert not changed, f"Installed app differs from fixture: {changed}"
        assert not xattr.exists(), "Installer invoked xattr on the app"
        cli = home / ".local/bin/fantasma"
        assert os.readlink(cli) == str(installed / "Contents/MacOS/Fantasma")
        assert launch.read_text().splitlines() == [str(installed)]


if __name__ == "__main__":
    installer = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parents[1] / "install.sh"
    test_release_install(installer.resolve())
