# CameraProbe for Windows - handoff / plan

This file is written for a fresh Claude session (or a human) starting the Windows port with no memory of the macOS work. Read it first, then read the macOS sources under `Sources/CameraProbe/` for exact behavior - they are the reference implementation.

## What CameraProbe does

A background tray/menu bar utility. When the computer's camera turns on or off it:

1. Switches a physical "on air" relay (ESP8266 on the LAN) via HTTP.
2. Fires Home Assistant webhooks.
3. Shows a red dot on its own tray icon while the camera is in use.

Everything is configured from a Preferences window. The macOS version (v2.0.0, Swift/AppKit) is finished and lives in this repo on the `gui-menubar-app` branch. The Windows version is a **rewrite, not a port**: the macOS code relies on the unified log, AppKit, `NSWorkspace`, and `SMAppService`, none of which exist on Windows. The relay firmware, Home Assistant side, and config schema are shared and unchanged.

## Behavior to reproduce exactly

**Camera on:**
- Detect camera start. Wait `activeApplicationDetectionDelay` = 3 seconds, then determine which application has the camera (on macOS this is the frontmost app; on Windows the registry gives the real app - see below).
- If the app is in `ignoredApplications` (case-insensitive match) OR Inactivate is on: send nothing for this session.
- Otherwise: `GET /on` to the relay, and POST the `camera_on` webhook with the application name.

**Camera off:**
- Send `GET /off` and the `camera_off` webhook **only if the matching "on" was actually sent** for that session. Never send a lone "off" with no preceding "on".
- If the camera turns off during the 3-second wait, do not send "on" at all (macOS uses a generation counter for this - see `CameraState` in `CameraMonitor.swift`).

**Relay HTTP** (firmware in `firmware/CameraProbeRelay/`): `GET http://{host}:{port}/on`, `/off`, `/status` (`/status` returns the text `ON` or `OFF`). 5-second timeouts.

**Home Assistant:** `POST http://{host}:{port}/api/webhook/camera_on` or `camera_off`. For `camera_on`, the body is form-urlencoded `application=<percent-encoded app name>` with `Content-Type: application/x-www-form-urlencoded`. `camera_off` has no body. See `homeassistant/README.md` for the automations. 5-second timeouts.

Both integrations are independently enableable. When one is disabled, calls to it are skipped silently.

**Tray icon dot:** the red dot reflects ONLY CameraProbe's own local detection: it is on exactly when the camera is in use by a non-excluded app AND Inactivate is off. It is independent of the relay and Home Assistant (not gated on whether they are enabled, configured, or reachable), updates instantly (no polling of the relay), and goes dark immediately when Inactivate is toggled on. The user specifically asked for this; do not tie it to relay status.

**Tray menu:** About, Preferences..., Inactivate/Reactivate (label toggles; pauses relay + Home Assistant notifications while detection keeps running), Quit.

**Preferences window:** relay enabled/host/port, Home Assistant enabled/host/port, ignored applications (one per line), Start at Login. Validate ports 1-65535 and non-empty hosts. Save writes the config file and applies immediately with no restart.

**Splash screen:** brief (about 1.5s) borderless window at launch showing the app icon, name/version, and "Starting up...".

**CLI flags** (kept for scripting/troubleshooting): `--version`, `--help`, `--status` (relay, Home Assistant, Start at Login, monitor running), `--test` (DNS, relay, Home Assistant reachability, camera detection access, Start at Login; non-zero exit on failure). Handle these before showing any UI and exit.

## Config file

macOS: `~/Library/Application Support/CameraProbe/config.json`. **Windows: `%APPDATA%\CameraProbe\config.json`**, same schema:

```json
{
  "relay":         { "enabled": true, "host": "onair.local",          "port": 80 },
  "homeAssistant": { "enabled": true, "host": "homeassistant.local",  "port": 8123 },
  "ignoredApplications": []
}
```

Every field is optional; missing fields use the defaults shown. A malformed file logs a warning and falls back to all defaults - it must never prevent startup. Keep the in-memory config behind a lock and let the Preferences window replace it live. `config.example.json` in the repo root is the template.

## Windows implementation plan

**Stack:** C# on .NET 8, WinForms (simplest for a tray app). Visual Studio 2022 Community or VS Code with the C# Dev Kit. Put the project in a new folder (e.g. `windows/CameraProbe.Windows/`) so the macOS sources are untouched.

**Camera detection:** Windows records camera use in the registry:
`HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam`
- Packaged (Store) apps have a subkey named by package family name.
- Desktop apps are under a `NonPackaged` subkey; the subkey name is the exe path with `\` replaced by `#`.
- Each app subkey has `LastUsedTimeStart` and `LastUsedTimeStop` (QWORD, Windows FILETIME). Camera is in use by that app when Start is non-zero and Stop is 0.
- Poll about once per second across all app subkeys (or use `RegNotifyChangeKeyValue`). Derive a friendly app name from the exe filename / package name; this should be more accurate than the macOS frontmost-app guess, so the 3-second delay may be reducible - but keep it unless testing shows it is unnecessary.
- **This is from memory and must be verified on the NUC with a real USB webcam** before building on it. Check how the keys behave with several apps (Camera app, browser, Teams/Zoom) and note any Windows 11 version differences.

**Tray:** `NotifyIcon` + `ContextMenuStrip`. Windows has no overlay-subview equivalent, so draw the red dot into the tray icon bitmap (swap between a plain and a dotted icon at 16x16 and 32x32 for HiDPI). Single-instance guard via a named `Mutex`.

**Start at Login:** value under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

**HTTP:** one shared `HttpClient` with a 5-second timeout. mDNS `.local` names usually resolve on Windows 10/11, but if not, fall back to an IP in config and note it in the docs.

**Icon:** convert `Resources/AppIcon.svg` (tally-light design: lens ring, glowing red dot, "ON AIR" badge) to a multi-size `.ico` (16, 32, 48, 256) with ImageMagick. A cleaner mono/simplified variant may read better at 16px in the tray.

**Packaging:** Inno Setup (or WiX/MSIX) installer; unsigned builds trigger SmartScreen warnings, comparable to Gatekeeper on macOS. A code-signing certificate removes them but costs money - not required to start.

**Logging:** write to a log file under `%APPDATA%\CameraProbe\` (and/or Windows Event Log). The macOS app uses OSLog subsystem `com.tim.cameraprobe`.

## Tools needed on the build machine (Windows 11 Pro NUC)

.NET 8 SDK, Visual Studio 2022 Community or VS Code + C# Dev Kit, Git for Windows, GitHub CLI (`gh`), ImageMagick, Inno Setup. A USB webcam to test detection, and the NUC on the same LAN as the relay (`onair.local`) and Home Assistant. Hyper-V is only needed if running Claude's Cowork mode on the NUC; it is not needed to build or run CameraProbe.

## macOS source map (reference)

| File | What it does |
|---|---|
| `CameraMonitor.swift` | Camera state machine, generation counter, ignore/pause logic, `CameraActivityIndicator` |
| `Relay.swift`, `HomeAssistant.swift` | The HTTP calls above |
| `Configuration.swift` | Config schema, defaults, live `ConfigStore` |
| `StatusBarController.swift` | Tray icon, menu, red dot |
| `SettingsWindowController.swift` | Preferences window |
| `SplashWindowController.swift` | Launch splash |
| `PauseState.swift` | Inactivate state |
| `LoginItem.swift` | Start at Login |
| `Diagnostics.swift` | `--test` / `--status` / `--help` |

`RelayStatusPoller.swift` exists but is intentionally unused (the dot no longer polls the relay).

## Ground rules from the macOS project

- The repo is **public**. Never commit WiFi credentials or real configs: `firmware/CameraProbeRelay/secrets.h` and `config.json` are gitignored - keep it that way.
- Don't delete the user's files without asking.
- Keep docs (README / INSTALL / CHANGELOG) updated with each user-visible change, and keep the macOS app working.
- Work on a dedicated branch (e.g. `windows`) created from `gui-menubar-app` (or `main` once that is merged), and let the user commit/push.

## Suggested first steps

1. Clone the repo, check out the new branch, read the macOS sources listed above.
2. Prove camera detection first: a small console app that watches the registry keys and prints app name + on/off, tested with a real webcam. Everything else depends on it.
3. Add config loading/saving, then the relay and Home Assistant calls with a `--test` CLI.
4. Add the tray icon, menu, red dot, and Inactivate.
5. Add the Preferences window, Start at Login, and splash.
6. Icon conversion, installer, and docs.
