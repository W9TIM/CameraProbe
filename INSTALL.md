# Installing CameraProbe

## Upgrading from the old LaunchAgent-based install

If you previously installed CameraProbe via `./install.sh`, remove that first so the old LaunchAgent-run copy and the new menu bar app don't both try to run at once:

```
launchctl bootout gui/$(id -u)/com.tim.cameraprobe
rm -f ~/Library/LaunchAgents/com.tim.cameraprobe.plist
sudo rm -rf "/Applications/CameraProbe"
```

Before running the bootout, it's worth confirming which plist launchd actually has loaded:

```
launchctl print gui/$(id -u)/com.tim.cameraprobe
```

Check the `path` in the output. It should be under `~/Library/LaunchAgents/` - if it instead points at `/Library/LaunchAgents/com.tim.cameraprobe.plist` (system-wide), remove that copy too, with `sudo`:

```
sudo launchctl bootout gui/$(id -u)/com.tim.cameraprobe
sudo rm -f "/Library/LaunchAgents/com.tim.cameraprobe.plist"
```

Optional - the old install wrote its config system-wide; the new app doesn't read from there, so you can clean it up if you like:

```
sudo rm -rf "/Library/Application Support/CameraProbe"
```

None of this touches `~/Library/Application Support/CameraProbe/config.json` (the new per-user config), since that lives at a different path entirely.

## Prerequisites

- macOS 14 (Sonoma) or later.
- Xcode Command Line Tools, for the Swift toolchain:
  ```
  xcode-select --install
  ```
  Verify with `swift --version` - if that prints a version, you're set.
- (Optional) An HTTP-controlled relay reachable on your network, e.g. an ESP8266/ESP32 running Tasmota, exposing `GET /on`, `GET /off`, and `GET /status`.
- (Optional) A Home Assistant instance with webhook automations listening for `camera_on` and `camera_off`.

Both integrations can be disabled independently in Preferences if you only want one, or neither (e.g. just watching logs).

## Step by step

1. Get the code onto your Mac - clone the repository, or download and extract the zip - so you have a `CameraProbe` folder containing `Package.swift`.

2. Open Terminal and `cd` into that folder.

3. Build the app - **not** with `sudo`:
   ```
   ./build-app.sh
   ```
   This runs `swift build -c release`, assembles `dist/CameraProbe.app`, code-signs it with a stable identifier, and (if `hdiutil` is available, which it is by default on macOS) also produces `dist/CameraProbe.dmg`.

4. Install it the normal Mac way - no `sudo`, no installer script:
   - Open `dist/CameraProbe.dmg` and drag **CameraProbe** onto the **Applications** shortcut, or
   - Drag `dist/CameraProbe.app` directly into `/Applications` in Finder.

5. **First launch:** the app isn't notarized by Apple (it's signed ad-hoc, not with a paid Apple Developer certificate), so macOS's Gatekeeper will initially refuse to open it normally. Right-click `CameraProbe.app` in `/Applications`, choose **Open**, and confirm in the dialog that appears. This is a one-time step - after that, opening it normally (double-click, Spotlight, or as a login item) works fine.

6. A brief splash screen appears, then CameraProbe settles into the menu bar - look for the camera icon near the clock. It doesn't appear in the Dock; this is a background utility.

7. The **first time** CameraProbe makes a network connection, macOS shows a system dialog:
   > "CameraProbe" would like to find and connect to devices on your local network.

   Click **Allow**. This is macOS's Local Network privacy permission, not something CameraProbe can bypass or something gone wrong - every app that talks to `.local`/LAN devices needs this once. `build-app.sh` code-signs the app with a stable identifier specifically so this approval persists across future rebuilds (normally, an unsigned/ad-hoc-signed app gets a new identity - and a fresh prompt - every time it's rebuilt).

8. Click the menu bar icon → **Preferences…** and set your relay hostname/port and Home Assistant hostname/port (defaults are `onair.local:80` and `homeassistant.local:8123`). Turn on **Start at Login** here too, if you want CameraProbe to launch automatically. Click **Save** - changes apply immediately, no restart needed.

9. Test the camera detection: open Photo Booth or FaceTime, then check:
   ```
   log stream --predicate 'subsystem == "com.tim.cameraprobe"'
   ```
   You should see `CAMERA ON` followed by the detected application, then `CAMERA OFF` when you close it. The menu bar icon should also show a red dot while the relay is on.

## Verifying the install

From Terminal:

```
/Applications/CameraProbe.app/Contents/MacOS/CameraProbe --status
```

should show something like:

```
CameraProbe 2.0.0

Relay...............OK
Home Assistant......OK
Start at Login......Enabled
Camera Monitor......Running
```

For a deeper check (DNS, reachability, log access, Start at Login state, with pass/fail detail on each):

```
/Applications/CameraProbe.app/Contents/MacOS/CameraProbe --test
```

## Upgrading

Pull/copy the updated source, then run `./build-app.sh` again and drag the new `dist/CameraProbe.app` over the old one in `/Applications` (Finder will ask to replace it - confirm). Your settings in `~/Library/Application Support/CameraProbe/config.json` are untouched by this, since the app and its config live in separate places.

## Uninstalling

Turn off **Start at Login** in Preferences first if you'd enabled it, quit CameraProbe from the menu bar, then drag `CameraProbe.app` from `/Applications` to the Trash.

To also remove your saved settings:

```
rm -rf ~/Library/Application\ Support/CameraProbe
```

## Troubleshooting

**"CameraProbe" can't be opened because it is from an unidentified developer.** Right-click the app and choose **Open** instead of double-clicking - see step 5 above. This is expected for an ad-hoc-signed app and only needs doing once.

**Connectivity issues in `--test`/`--status`.** `.local` hostnames resolve over mDNS, which can be slow on a cold lookup. Confirm the hostname resolves and is reachable from a browser first (e.g. `http://onair.local/status`), then re-check.

**No Local Network permission dialog ever appeared.** Check System Settings → Privacy & Security → Local Network - if CameraProbe already has an entry there (from a previous build), you won't be re-prompted. Toggle it off and back on to re-trigger the prompt if you need to test it.

**Camera events aren't detected.** Run `--test` - the "Log stream access" check will fail with a detail message if `/usr/bin/log stream` can't run in your environment.

**Start at Login toggle in Preferences does nothing / is missing.** This only works when running the installed `.app` (it needs a real bundle identifier) - it's unavailable if you run the raw binary via `swift run` during development.
