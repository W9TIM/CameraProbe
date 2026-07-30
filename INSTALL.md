# Installing CameraProbe

## Prerequisites

- macOS 14 (Sonoma) or later.
- Xcode Command Line Tools, for the Swift toolchain:
  ```
  xcode-select --install
  ```
  Verify with `swift --version` - if that prints a version, you're set.
- (Optional) An HTTP-controlled relay reachable on your network, e.g. an ESP8266/ESP32 running Tasmota, exposing `GET /on` and `GET /off`.
- (Optional) A Home Assistant instance with webhook automations listening for `camera_on` and `camera_off`.

Both integrations can be disabled independently in the config file if you only want one, or neither (e.g. just watching logs).

## Step by step

1. Get the code onto your Mac - clone the repository, or download and extract the zip - so you have a `CameraProbe` folder containing `Package.swift`.

2. Open Terminal and `cd` into that folder.

3. Run the installer as your normal user - **not** with `sudo`:
   ```
   ./install.sh
   ```

4. If this is a first install (no existing config), you'll be prompted:
   ```
   Relay hostname [onair.local]:
   Relay port [80]:
   Home Assistant hostname [homeassistant.local]:
   Home Assistant port [8123]:
   ```
   Press Return to accept the default shown in brackets, or type your own value.

5. The script will ask for your password (via `sudo`) once, to install the binary to `/Applications/CameraProbe` and write the config to `/Library/Application Support/CameraProbe/config.json`.

6. It installs and loads a LaunchAgent (`~/Library/LaunchAgents/com.tim.cameraprobe.plist`) so CameraProbe starts automatically at login, and runs a connectivity check:
   ```
   ==> Verifying connectivity
     Relay            OK
     Home Assistant   OK
   ```

7. The **first time** the installed binary makes a network connection, macOS shows a system dialog:
   > "CameraProbe" would like to find and connect to devices on your local network.

   Click **Allow**. This is macOS's Local Network privacy permission, not something CameraProbe can bypass or something gone wrong - every app that talks to `.local`/LAN devices needs this once. The installer code-signs the binary with a stable identifier specifically so this approval persists across future reinstalls (normally, an unsigned/ad-hoc-signed binary gets a new identity - and a fresh prompt - on every rebuild).

8. Test the camera detection: open Photo Booth or FaceTime, then check:
   ```
   log stream --predicate 'subsystem == "com.tim.cameraprobe"'
   ```
   You should see `CAMERA ON` followed by the detected application, then `CAMERA OFF` when you close it.

## Verifying the install

```
CameraProbe --status
```

should show:

```
CameraProbe 1.0.0

Relay...............OK
Home Assistant......OK
LaunchAgent.........Loaded
Camera Monitor......Running
```

For a deeper check (DNS, reachability, log access, LaunchAgent state, with pass/fail detail on each):

```
CameraProbe --test
```

## Upgrading

Pull/copy the updated source, then just run `./install.sh` again from the project folder. It rebuilds, reinstalls, re-signs, and reloads the LaunchAgent. Your existing `config.json` is left untouched.

## Uninstalling

```
./uninstall.sh
```

## Troubleshooting

**"Please run this as your normal user, not with sudo."** Run `./install.sh` (or `./uninstall.sh`) directly - it elevates only the specific commands that need it. Running the whole script under `sudo` breaks the LaunchAgent step, since a per-user LaunchAgent has to be loaded as that user, not as root.

**Connectivity check shows UNREACHABLE.** `.local` hostnames resolve over mDNS, which can be slow on a cold lookup; the checks in `install.sh` account for this, but a genuinely unreachable host (wrong hostname, device powered off, wrong network) will still fail. Confirm the hostname resolves and is reachable from a browser first, then re-run `./install.sh`.

**No Local Network permission dialog ever appeared.** Check System Settings → Privacy & Security → Local Network - if CameraProbe already has an entry there (from a previous install), you won't be re-prompted. Toggle it off and back on to re-trigger the prompt if you need to test it.

**Camera events aren't detected.** Run `CameraProbe --test` - the "Log stream access" check will fail with a detail message if `/usr/bin/log stream` can't run in your environment.
