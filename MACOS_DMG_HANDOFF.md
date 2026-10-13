# Attach the macOS .dmg to the v2.0.0 release - handoff

This file is for a fresh Claude session (or a human) on the Mac. It needs no memory of the Windows work.

## Background

The GitHub release [CameraProbe 2.0.0](https://github.com/W9TIM/CameraProbe/releases/tag/v2.0.0) (tag `v2.0.0`) covers both the macOS 2.0.0 menu bar app and the new Windows 2.0.0 tray app. It was created from Windows, so it only has the Windows installer (`CameraProbe-Setup-2.0.0.exe`). A `.dmg` can only be built on a Mac, so the macOS download is missing. The release notes currently tell Mac users to build from source with `./build-app.sh`.

## Steps

1. **Get the release's exact source.** The `v2.0.0` tag is what the release was made from:
   ```bash
   git fetch --tags && git checkout v2.0.0
   ```
   `main` works too: after the tag it only has docs changes and the Windows test apps' removal, so the macOS app is identical.

2. **Build the app and disk image:**
   ```bash
   ./build-app.sh
   ```
   This produces `dist/CameraProbe.app` and `dist/CameraProbe.dmg`. Check it opens and runs before uploading.

3. **Attach the .dmg to the release.** This needs the GitHub CLI, installed (`brew install gh`) and signed in (`gh auth login`):
   ```bash
   gh release upload v2.0.0 dist/CameraProbe.dmg --repo W9TIM/CameraProbe
   ```

4. **Update the release notes** (`gh release edit v2.0.0 --repo W9TIM/CameraProbe --notes-file <file>`, starting from the current body via `gh release view v2.0.0 --repo W9TIM/CameraProbe --json body --jq .body`):
   - In the macOS section, replace the build-from-source line with "Download `CameraProbe.dmg` below, open it and drag CameraProbe to Applications", keeping the 1.x LaunchAgent upgrade note.
   - Add the `.dmg`'s SHA-256 (`shasum -a 256 dist/CameraProbe.dmg`) next to the existing Windows one.

5. **Tidy up:** once done, delete this file from the repo (it's a one-off handoff) via a small PR, or ask the user.

## Ground rules

- The repo is **public**. Don't commit `firmware/CameraProbeRelay/secrets.h` or any real `config.json` (both are gitignored).
- Don't change the `v2.0.0` tag or rebuild the Windows installer; only add the `.dmg` and edit the notes.
- Ask before publishing changes to the release if anything looks different from what's described here.
