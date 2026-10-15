# CameraProbe

A macOS menu bar utility that watches for camera activity and reacts to it: flips a physical "on air" relay, and/or fires a Home Assistant webhook, whenever your Mac's camera turns on or off.

Ships as a normal `.app` you drag into `/Applications` - no installer, no `sudo`, no LaunchAgent. It lives in the menu bar with a custom tally-light icon, shows a red dot on top of it whenever the camera is actively in use, and everything is configured from a Preferences window.

> **Windows:** a Windows 10/11 tray version (2.0.0, matching this macOS release) lives in [`windows/`](windows/README.md). It uses the same relay firmware, Home Assistant webhooks and config schema. The rest of this README covers the macOS app.

## Features

- Detects camera start/stop by watching the unified log stream for `cameracaptured` events - no polling, no private APIs.
- Reports which application grabbed the camera (Zoom, FaceTime, Photo Booth, Teams, browsers, etc.).
- Controls an HTTP-controlled relay (e.g. an ESP8266/ESP32 running Tasmota or custom firmware) for a physical "on air" light.
- Fires Home Assistant webhooks (`camera_on` / `camera_off`) so you can build automations on top of camera state.
- Menu bar icon shows a red dot the instant CameraProbe itself detects the camera in use by a non-excluded app - a local, independent signal that doesn't depend on the relay or Home Assistant being enabled, configured, or reachable. Goes dark while Inactivate is on.
- Right-click menu: About, Preferences, Inactivate/Reactivate (pause relay + Home Assistant notifications without quitting - camera detection keeps running), Quit.
- Preferences window for relay, Home Assistant, ignored apps, and Start at Login - no manual config-file editing required. Changes apply immediately, no restart.
- `ignoredApplications` exclude list - apps that activate the camera without ever notifying the relay/Home Assistant (privacy, gameplay capture, etc.), editable from Preferences.
- Self-healing: if the underlying log-stream process dies, it restarts automatically with backoff.
- `CameraProbe --test` and `CameraProbe --status` for command-line diagnostics.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools (to build from source): `xcode-select --install`.
- An HTTP-controlled relay reachable on your LAN (optional - can be disabled in Preferences).
- A Home Assistant instance with webhook automations for `camera_on` / `camera_off` (optional - can be disabled in Preferences).

## Download

Prebuilt installers are on the [**latest release**](https://github.com/W9TIM/CameraProbe/releases/latest) page:

- **macOS:** `CameraProbe.dmg` - open it and drag **CameraProbe** onto **Applications**.
- **Windows:** `CameraProbe-Setup-<version>.exe` - run it (see [`windows/README.md`](windows/README.md#install)).

Neither is signed or notarized, so your OS will warn on first launch - see **First launch** below (macOS) or the Windows README (SmartScreen: **More info → Run anyway**). Prefer to build it yourself? Use the steps below.

## Install (build from source)

```
git clone <this repository>
cd CameraProbe
./build-app.sh
```

This builds the release binary and assembles `dist/CameraProbe.app` (plus `dist/CameraProbe.dmg`). No `sudo` at any point.

Then either:

- Open `dist/CameraProbe.dmg` and drag **CameraProbe** onto the **Applications** shortcut, or
- Drag `dist/CameraProbe.app` straight into `/Applications` in Finder.

**First launch:** the app isn't notarized by Apple, so right-click `CameraProbe.app` in `/Applications` and choose **Open**, then confirm - after that first approval, opening it normally (double-click, Spotlight, login item) works fine. If macOS still refuses, open **System Settings → Privacy & Security**, scroll to the message about CameraProbe, and click **Open Anyway**.

A brief splash screen (showing the app's own tally-light icon) appears, then CameraProbe settles into the menu bar (look for the tally-light icon near the clock - no Dock icon, this is a background utility). The first time it talks to the network, macOS shows a **Local Network** permission prompt - click **Allow**. `build-app.sh` code-signs the app with a stable identifier specifically so this approval survives future rebuilds.

Open the menu bar icon → **Preferences…** to set your relay and Home Assistant hostnames, and optionally turn on **Start at Login**.

See [INSTALL.md](INSTALL.md) for a more detailed walkthrough and troubleshooting.

## Configuration

Preferences window (menu bar icon → **Preferences…**) is the normal way to change settings - relay enabled/host/port, Home Assistant enabled/host/port, ignored applications, and Start at Login. Saving writes to disk and takes effect immediately, no restart needed.

Under the hood, this is stored at `~/Library/Application Support/CameraProbe/config.json`:

```json
{
  "relay": {
    "enabled": true,
    "host": "onair.local",
    "port": 80
  },
  "homeAssistant": {
    "enabled": true,
    "host": "homeassistant.local",
    "port": 8123
  },
  "ignoredApplications": []
}
```

Every field is optional - anything you omit falls back to the default shown above. You can hand-edit this file directly if you prefer (per-user path, no `sudo` needed); CameraProbe doesn't watch it for external changes, though, so use Preferences if the app is already running. A malformed config file is logged as a warning and CameraProbe falls back to defaults rather than failing to start.

**`ignoredApplications`** is an exclude list: every app that activates the camera still triggers a notification by default (empty list), but you can name specific apps to skip - for privacy (e.g. Photo Booth) or gameplay capture you don't want broadcasting "on air". Add them one per line in Preferences, or as a JSON array:

```json
"ignoredApplications": ["Photo Booth", "OBS"]
```

Matching is case-insensitive and uses the same app name CameraProbe logs/reports (`log stream --predicate 'subsystem == "com.tim.cameraprobe"'` will show you the exact name it detected if you're not sure). When an ignored app is what grabbed the camera, neither the relay nor Home Assistant gets notified for that session - including the matching "off" event, so you won't see a stray "camera off" with no preceding "on".

See `config.example.json` for a copyable template.

## Usage

CameraProbe normally just runs in the menu bar, but the same binary supports a few commands directly from Terminal (handy for scripting/troubleshooting):

```
CameraProbe                Launch the menu bar app (splash screen, then runs in the menu bar)
CameraProbe --status       One-shot summary: relay, Home Assistant, Start at Login, camera monitor
CameraProbe --test         Full diagnostics: DNS, relay, Home Assistant, log access, Start at Login
CameraProbe --version      Print the version
CameraProbe --help         Show usage
```

Example `--status` output:

```
CameraProbe 2.0.0

Relay...............OK
Home Assistant......OK
Start at Login......Enabled
Camera Monitor......Running
```

Live logs:

```
log stream --predicate 'subsystem == "com.tim.cameraprobe"'
```

## Uninstall

Turn off **Start at Login** in Preferences first (if you'd enabled it), then quit CameraProbe from the menu bar and drag `CameraProbe.app` from `/Applications` to the Trash. That's it - no installer to run in reverse.

To also remove your saved settings:

```
rm -rf ~/Library/Application\ Support/CameraProbe
```

If you're upgrading from the older LaunchAgent-based install, see the note at the top of [INSTALL.md](INSTALL.md) for how to remove that first.

## How it works

CameraProbe shells out to `/usr/bin/log stream` with a predicate that matches `cameracaptured`'s `DidStartRunning`/`DidStopRunning` events - the same signal macOS's own camera indicator light relies on. When the camera turns on, it waits briefly (to let the capturing app become frontmost), asks `NSWorkspace` which application is active, then notifies the relay and Home Assistant (unless the app is in `ignoredApplications`, or Inactivate is on). When it turns off, both get an "off" notification immediately.

The menu bar's red dot is driven by that same local detection, independently of whether the relay/Home Assistant notifications actually went out: it lights up the instant a non-excluded app grabs the camera, and goes dark the instant the camera is released or Inactivate is toggled on. It never polls or depends on the relay or Home Assistant being enabled, configured, or reachable - it's purely "does CameraProbe itself currently consider the camera in use."

## Relay firmware

The `firmware/` folder has two ESP8266 sketches that run the physical relay CameraProbe talks to by default, one per hardware option: a **Wemos D1 Mini with relay shield** (`CameraProbeRelay/`) and a more compact **ESP-01S relay module** (`CameraProbeRelay8266/`) - see [firmware/README.md](firmware/README.md) for which to choose, wiring, Arduino IDE setup, and flashing instructions. If you already have relay hardware exposing `GET /on` / `GET /off` / `GET /status`, you don't need it; just point the relay host in Preferences (or `config.json`) at your existing device.

The low voltage relay is used for controlling power to a 5V (USB) light (On/Off) via WiFi. The control unit is constructed with a Wemos D1 Mini (ESP8266) with a single relay shield attached.

This can be housed in a simple 3D printable enclosure and mounted near or for shaddow box lights, inside to keep it out of the way. This arrangement will require two USB connections. One to power the Wemos D1 and one to power the light itself, which will be switched on/off when the +5v line is interrupted by the relay shield. 

Photos and 3D-printable files are included with this project:

- **ESP-01S relay case:** a compact two-part enclosure (base and friction-fit lid) - print-ready [STL](firmware/ESP8266%20Module%20Device/ESP01S_Relay_Case.stl), editable [OpenSCAD source](firmware/ESP8266%20Module%20Device/ESP01S_Relay_Case.scad), and the [design spec](firmware/ESP8266%20Module%20Device/CASE_DESIGN_SPEC.md). Includes a single-supply wiring photo and diagram in [firmware/README.md](firmware/README.md#single-supply-wiring-esp-01s-relay-variant).
- **Wemos D1 Mini case:** see the `3D Printable Files` folder under `firmware/`.

## Home Assistant setup

CameraProbe calls two built-in Home Assistant webhooks (`camera_on` / `camera_off`) - see [homeassistant/README.md](homeassistant/README.md) for how to wire those up to an automation, with both a UI walkthrough and a copyable YAML example.

## Project layout

**Sources/CameraProbe/**

| File | Purpose |
|---|---|
| `main.swift` | Entry point: CLI flag parsing, launches the menu bar app |
| `AppDelegate.swift` | App lifecycle: splash screen, signal handling, startup |
| `StatusBarController.swift` | Menu bar icon, right-click menu, camera-activity dot overlay |
| `SettingsWindowController.swift` | Preferences window |
| `SplashWindowController.swift` | Brief launch splash screen (shows the app icon) |
| `PauseState.swift` | Inactivate/Reactivate state |
| `LoginItem.swift` | Start at Login (`SMAppService`) |
| `Configuration.swift` | Config schema, per-user config file, live `ConfigStore` |
| `Logger.swift` | OSLog setup, startup banner |
| `CameraMonitor.swift` | Camera state + log-stream subprocess management |
| `Relay.swift` | Relay HTTP calls |
| `HomeAssistant.swift` | Home Assistant webhook calls |
| `ActiveApplication.swift` | Frontmost-app lookup |
| `Diagnostics.swift` | `--test` / `--status` / `--help` implementation |
| `Utilities.swift` | DNS check |

**Other top-level files and folders**

| Path | Purpose |
|---|---|
| `Package.swift` | Swift package manifest |
| `build-app.sh` | Builds `dist/CameraProbe.app` and `dist/CameraProbe.dmg` |
| `Info.plist.template` | App bundle metadata used by `build-app.sh` |
| `Resources/AppIcon.svg`, `Resources/AppIcon.iconset/` | App icon source and compiled sizes - see "App icon" below |
| `config.example.json` | Copyable config template |
| `firmware/` | ESP8266 relay sketch, wiring docs, WiFi credentials template |
| `homeassistant/` | Home Assistant automation setup docs and example YAML |
| `windows/` | The Windows tray app (C#/.NET 8) - see [`windows/README.md`](windows/README.md) |
| `WINDOWS_PORT.md` | Windows port plan and camera-detection test findings |
| `install.sh`, `uninstall.sh`, `com.tim.cameraprobe.plist.template` | Legacy LaunchAgent installer - superseded by `build-app.sh`, kept for reference |
| `README.md`, `INSTALL.md`, `CHANGELOG.md`, `LICENSE` | Project docs |

## App icon

The icon is a custom "tally light" design - a camera lens with a glowing red indicator and an ON AIR badge, matching the menu bar's own activity dot visually. Source files live under `Resources/`:

- `Resources/AppIcon.svg` - the editable vector source.
- `Resources/AppIcon.iconset/` - the 10 PNG sizes Apple requires, generated from the SVG.

`build-app.sh` compiles the iconset into `AppIcon.icns` via `iconutil` (bundled with Xcode) and embeds it in `CameraProbe.app/Contents/Resources/`, referenced from `Info.plist.template`'s `CFBundleIconFile`. It also stamps the same icon onto `dist/CameraProbe.dmg` as the disk image's own volume icon (via `SetFile`, skipped with a warning if that tool isn't installed - the app's icon isn't affected either way). The splash screen shown at launch displays this same icon (`NSApp.applicationIconImage`), falling back to a generic system icon only when running unbundled (e.g. `swift run` during development, before Info.plist's icon applies).

To change the artwork: edit or regenerate `Resources/AppIcon.svg`, re-render it to the 10 PNG sizes listed in `Resources/AppIcon.iconset/`, and run `./build-app.sh` again - no other changes needed.

## Troubleshooting

**macOS says the app "can't be opened because it is from an unidentified developer."** Right-click (not double-click) `CameraProbe.app` in `/Applications` and choose **Open**, then confirm in the dialog. This is only needed once - it's Gatekeeper reacting to an ad-hoc-signed, non-notarized app, not a sign of a broken build.

**Local Network permission dialog reappears after a rebuild.** This means the app's signature changed. `build-app.sh` re-signs it with a fixed identifier each time specifically to prevent this - make sure you're rebuilding via `./build-app.sh` rather than copying the binary manually.

**Preferences changes don't seem to apply.** They take effect immediately in the running app - no restart needed. If it still looks stale, confirm you clicked **Save** (not the titlebar close button), and check `~/Library/Application Support/CameraProbe/config.json`'s contents directly.

**Nothing happens when the camera turns on.** Run `CameraProbe --test` (from Terminal: `/Applications/CameraProbe.app/Contents/MacOS/CameraProbe --test`) to check each subsystem individually, and `log stream --predicate 'subsystem == "com.tim.cameraprobe"'` to watch live logs while triggering the camera (e.g. open Photo Booth). Also check the menu bar icon isn't showing "Inactivate" as reversed to "Reactivate" (meaning notifications are currently paused).

**Upgrading from the old LaunchAgent-based install.** See the note at the top of [INSTALL.md](INSTALL.md) - remove the LaunchAgent first to avoid two copies of CameraProbe running at once.

## License

MIT - see [LICENSE](LICENSE).
