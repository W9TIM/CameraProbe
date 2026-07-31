# CameraProbe

A macOS background utility that watches for camera activity and reacts to it: flips a physical "on air" relay, and/or fires a Home Assistant webhook, whenever your Mac's camera turns on or off.

Runs as a LaunchAgent, so it starts automatically at login and stays out of the way.

## Features

- Detects camera start/stop by watching the unified log stream for `cameracaptured` events - no polling, no private APIs.
- Reports which application grabbed the camera (Zoom, FaceTime, Photo Booth, Teams, browsers, etc.).
- Controls an HTTP-controlled relay (e.g. an ESP8266/ESP32 running Tasmota or custom firmware) for a physical "on air" light.
- Fires Home Assistant webhooks (`camera_on` / `camera_off`) so you can build automations on top of camera state.
- Configuration lives in a JSON file, not compiled-in constants - change a hostname without rebuilding.
- Self-healing: if the underlying log-stream process dies, it restarts automatically with backoff.
- `CameraProbe --test` and `CameraProbe --status` for quick diagnostics.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools (for `swift build`): `xcode-select --install`.
- An HTTP-controlled relay reachable on your LAN (optional - can be disabled in config).
- A Home Assistant instance with webhook automations for `camera_on` / `camera_off` (optional - can be disabled in config).

## Install

```
git clone <this repository>
cd CameraProbe
./install.sh
```

Run it as your normal user, **not** with `sudo` - it prompts for your password only for the specific steps that need elevated access (installing to `/Applications`, writing the system-wide config).

On first install it'll ask for your relay and Home Assistant hostnames (defaults shown in brackets, just press Return to accept). It then builds the release binary, installs it, creates the LaunchAgent, and runs a connectivity check.

The first time the installed binary talks to the network, macOS will show a **Local Network** permission prompt - click Allow. The binary is code-signed with a stable identifier during install specifically so this approval survives future reinstalls after code changes.

See [INSTALL.md](INSTALL.md) for a more detailed walkthrough and troubleshooting.

## Configuration

`/Library/Application Support/CameraProbe/config.json`:

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

Every field is optional - anything you omit falls back to the default shown above. Edit this file and restart CameraProbe (`launchctl kickstart -k gui/$(id -u)/com.tim.cameraprobe`) to pick up changes; no rebuild needed. A malformed config file is logged as a warning and CameraProbe falls back to defaults rather than failing to start.

**`ignoredApplications`** is an exclude list: every app that activates the camera still triggers a notification by default (empty list, same as before this existed), but you can name specific apps to skip - for privacy (e.g. Photo Booth) or gameplay capture you don't want broadcasting "on air":

```json
"ignoredApplications": ["Photo Booth", "OBS"]
```

Matching is case-insensitive and uses the same app name CameraProbe logs/reports (`log stream --predicate 'subsystem == "com.tim.cameraprobe"'` will show you the exact name it detected if you're not sure). When an ignored app is what grabbed the camera, neither the relay nor Home Assistant gets notified for that session - including the matching "off" event, so you won't see a stray "camera off" with no preceding "on".

See `config.example.json` for a copyable template.

## Usage

CameraProbe normally runs unattended under the LaunchAgent, but the binary supports a few commands directly:

```
CameraProbe                Start monitoring (this is what the LaunchAgent runs)
CameraProbe --status       One-shot summary: relay, Home Assistant, LaunchAgent, camera monitor
CameraProbe --test         Full diagnostics: DNS, relay, Home Assistant, log access, LaunchAgent
CameraProbe --version      Print the version
CameraProbe --help         Show usage
```

Example `--status` output:

```
CameraProbe 1.0.0

Relay...............OK
Home Assistant......OK
LaunchAgent.........Loaded
Camera Monitor......Running
```

Live logs:

```
log stream --predicate 'subsystem == "com.tim.cameraprobe"'
```

## Uninstall

```
./uninstall.sh
```

Stops and removes the LaunchAgent and the installed app, and asks before removing your configuration file.

## How it works

CameraProbe shells out to `/usr/bin/log stream` with a predicate that matches `cameracaptured`'s `DidStartRunning`/`DidStopRunning` events - the same signal macOS's own camera indicator light relies on. When the camera turns on, it waits briefly (to let the capturing app become frontmost), asks `NSWorkspace` which application is active, then notifies the relay and Home Assistant. When it turns off, both get an "off" notification immediately.

## Relay firmware

The `firmware/` folder has the ESP8266 sketch (Wemos D1 Mini) that runs the physical relay CameraProbe talks to by default - see [firmware/README.md](firmware/README.md) for wiring, Arduino IDE setup, and flashing instructions. If you already have relay hardware exposing `GET /on` / `GET /off`, you don't need it; just point `relay.host` in `config.json` at your existing device.

The low voltage relay is used for controlling power to a 5V (USB) light (On/Off) via WiFi. The control unit is constructed with a Wemos D1 Mini (ESP8266) with a single relay shield attached.

This can be housed in a simple 3D printable enclosure and mounted near or for shaddow box lights, inside to keep it out of the way. This arrangement will require two USB connections. One to power the Wemos D1 and one to power the light itself, which will be switched on/off when the +5v line is interrupted by the relay shield. 

Photo's and 3D Printable files are included with this project.

## Home Assistant setup

CameraProbe calls two built-in Home Assistant webhooks (`camera_on` / `camera_off`) - see [homeassistant/README.md](homeassistant/README.md) for how to wire those up to an automation, with both a UI walkthrough and a copyable YAML example.

## Project layout

```
CameraProbe/
├── Package.swift
├── Sources/CameraProbe/
│   ├── main.swift              Entry point: CLI flag parsing, startup, signal handling
│   ├── Configuration.swift     Config file schema, loading, shared constants
│   ├── Logger.swift            OSLog setup, startup banner
│   ├── CameraMonitor.swift     Camera state + log-stream subprocess management
│   ├── Relay.swift             Relay HTTP calls
│   ├── HomeAssistant.swift     Home Assistant webhook calls
│   ├── ActiveApplication.swift Frontmost-app lookup
│   ├── Diagnostics.swift       --test / --status / --help implementation
│   └── Utilities.swift         DNS check
├── firmware/
│   ├── README.md                          Wiring, Arduino IDE setup, flashing
│   └── CameraProbeRelay/
│       ├── CameraProbeRelay.ino            ESP8266 relay controller sketch
│       └── secrets.h.example               WiFi credentials template (copy to secrets.h)
├── homeassistant/
│   ├── README.md                           UI + YAML setup instructions
│   └── automations.example.yaml            Copyable automation definitions
├── install.sh
├── uninstall.sh
├── com.tim.cameraprobe.plist.template
├── config.example.json
├── README.md
├── INSTALL.md
├── CHANGELOG.md
└── LICENSE
```

## Troubleshooting

**"UNREACHABLE" during install, but the app works fine once running.** `.local` mDNS hostnames can be slow on a cold lookup, and `curl` doesn't race IPv4/IPv6 the way `URLSession` does. The install script warms the resolver and forces IPv4 before checking, but a genuinely flaky network can still produce a false negative here - run `CameraProbe --test` afterward to double check.

**Local Network permission dialog reappears after a rebuild.** This means the binary's signature changed. `install.sh` re-signs it with a fixed identifier each time specifically to prevent this - make sure you're reinstalling via `./install.sh` rather than copying the binary manually.

**Nothing happens when the camera turns on.** Run `CameraProbe --test` to check each subsystem individually, and `log stream --predicate 'subsystem == "com.tim.cameraprobe"'` to watch live logs while triggering the camera (e.g. open Photo Booth).

## License

MIT - see [LICENSE](LICENSE).
