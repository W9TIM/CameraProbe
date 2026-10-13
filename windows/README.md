# CameraProbe for Windows

A Windows 10/11 tray utility that watches for camera activity and reacts to it: flips the physical "on air" relay and/or fires Home Assistant webhooks whenever the camera turns on or off. It is the Windows counterpart of the macOS menu bar app in this repo - same relay firmware, same Home Assistant webhooks, same config schema.

**Version 2.0.0**, matching the macOS app. Tested on Windows 11 Pro 26H2 (build 26300) with a USB webcam, using the Windows Camera app, Chrome and Zoom.

## Features

- Detects camera start/stop with the Windows sensor activity monitor (Media Foundation), which reports the actual app using the camera - not a guess from the foreground window.
- Controls the HTTP relay (`GET /on`, `/off`) and fires Home Assistant webhooks (`camera_on` with the app name, `camera_off`).
- Tray icon whose tally light glows red while the camera is in use by a non-ignored app. Driven only by local detection: it doesn't depend on the relay or Home Assistant being enabled or reachable, and goes dark while Inactivate is on.
- Right-click menu: About, Preferences, Inactivate/Reactivate, Quit. Double-click the icon to open Preferences. About has quick links to the config and log files.
- Preferences window for relay, Home Assistant, ignored apps and Start at Login. Changes apply immediately.
- `CameraProbe --test` / `--status` / `--version` / `--help` from a terminal.

### Differences from the macOS app

- **No 3-second delay** before "on": Windows reports the app using the camera directly.
- **2-second off grace:** the camera only counts as off once it has stayed off for 2 seconds. Browser pages often restart the camera several times in quick succession, which would otherwise flicker the relay.
- **Quit and sign-out send "off"** if an "on" was sent for the current session, so the light isn't left on.
- Ignored applications match the app's display name, exe name or exe file name - e.g. `Zoom Meetings`, `Zoom` or `Zoom.exe`. The name used is shown in the log.

## Requirements

- Windows 10 or 11, x64.
- [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) (x64). The installer checks for it.
- The relay and/or Home Assistant on your LAN (each optional - can be disabled in Preferences).

## Install

1. Build the installer (see below) or get `CameraProbe-Setup-<version>.exe`.
2. Run it. It installs per-user into `%LOCALAPPDATA%\Programs\CameraProbe` - no admin prompt. Tick **Start CameraProbe when I sign in** if you want it at login (also changeable later in Preferences).
3. The installer isn't code-signed, so SmartScreen may warn: choose **More info -> Run anyway**.

CameraProbe then lives in the notification area (it may be under the **^** overflow - drag it onto the taskbar to keep it visible).

## Configuration

Use **Preferences** from the tray menu. Settings are saved to `%APPDATA%\CameraProbe\config.json`, same schema as macOS (see `config.example.json` in the repo root):

```json
{
  "relay":         { "enabled": true, "host": "onair.local",         "port": 80 },
  "homeAssistant": { "enabled": true, "host": "homeassistant.local", "port": 8123 },
  "ignoredApplications": []
}
```

Every field is optional. A malformed file is logged and ignored (defaults are used) - it never stops the app starting.

**`.local` names:** Windows 10/11 resolve mDNS names like `homeassistant.local`, but not every device answers reliably. If `CameraProbe --test` shows a DNS failure for a host, use its IP address instead (ideally a DHCP reservation on your router).

## Usage

The installer puts `CameraProbe.exe` (the tray app) and `CameraProbe.com` (a console shim) side by side. From cmd or PowerShell in the install folder, `CameraProbe` picks the `.com`, so output and exit codes work as expected:

```
cd %LOCALAPPDATA%\Programs\CameraProbe
CameraProbe --test      # DNS, relay, Home Assistant, camera access, Start at Login; exit code 1 on failure
CameraProbe --status    # relay, Home Assistant, Start at Login, whether the tray app is running
CameraProbe --version
CameraProbe --help
```

Log file: `%APPDATA%\CameraProbe\CameraProbe.log` (rolled over to `CameraProbe.old.log` past 1 MB). Every camera on/off, the app name, and each relay/Home Assistant call and its result are logged there.

## Uninstall

**Settings -> Apps -> Installed apps -> CameraProbe -> Uninstall.** This also removes the Start at Login entry. Your config and log in `%APPDATA%\CameraProbe` are kept; delete that folder too for a clean removal.

## Building from source

Needs the .NET 8 SDK (`winget install Microsoft.DotNet.SDK.8`). `windows/global.json` pins the .NET 8 SDK even when newer SDKs are installed.

```
cd windows
dotnet build CameraProbe.sln
CameraProbe.Cli\bin\Debug\net8.0-windows\CameraProbe.exe     # run the tray app
CameraProbe.Cli\bin\Debug\net8.0-windows\CameraProbe --test  # CLI via the .com shim
```

Installer (needs Inno Setup 6: `winget install JRSoftware.InnoSetup`):

```
powershell -ExecutionPolicy Bypass -File windows\build-installer.ps1
```

Output: `windows\dist\CameraProbe-Setup-<version>.exe`. The version comes from `windows/Directory.Build.props`.

Icons: the `.ico` files in `CameraProbe.Windows/Assets/` are committed. To regenerate them after changing the artwork, install ImageMagick (`winget install ImageMagick.ImageMagick`) and run `windows\make-icons.ps1`. `AppIcon.ico` comes from the macOS PNGs in `Resources/AppIcon.iconset/`; the tray icons come from `Assets/TrayIdle.svg` / `TrayActive.svg`, a simplified lens + tally light that stays readable at 16px.

## Project layout

| Path | Purpose |
|---|---|
| `CameraProbe.Windows/` | The app (WinForms, `WinExe` so no console window at login) |
| `CameraProbe.Cli/` | Console shim built as `CameraProbe.com` so shells wait for CLI output and exit codes. Its output folder is the complete app |
| `installer/CameraProbe.iss` | Inno Setup script |
| `build-installer.ps1`, `make-icons.ps1` | Installer and icon build scripts |
| `SensorProbe/`, `RegistryProbe/` | Throwaway camera-detection prototypes from the port - see `WINDOWS_PORT.md` |

Inside `CameraProbe.Windows/`:

| File | Purpose |
|---|---|
| `Program.cs` | Entry point: CLI flags, single-instance guard, starts the tray app |
| `TrayApp.cs` | Tray icon, menu, red tally light, Quit/sign-out handling, startup |
| `CameraMonitor.cs` | Camera session state machine (on/off rules, off grace, Inactivate, ignored apps) |
| `SensorActivity.cs` | Media Foundation sensor activity monitor interop |
| `CameraApp.cs` | PID -> app name / exe name, ignore-list matching |
| `Notifier.cs` | Relay and Home Assistant HTTP calls (ordered, 5-second timeouts) |
| `Configuration.cs` | Config schema, `%APPDATA%` config file, live `ConfigStore` |
| `PreferencesForm.cs`, `AboutForm.cs`, `SplashForm.cs` | Preferences window, About window, launch splash |
| `PauseState.cs` | Inactivate/Reactivate |
| `LoginItem.cs` | Start at Login (`HKCU\...\Run`) |
| `Diagnostics.cs` | `--test` / `--status` / `--help` / `--version` |
| `Log.cs`, `AppInfo.cs`, `TrayIcons.cs` | Log file, app identity, embedded icons |

## Troubleshooting

- **No red light when the camera is on:** check the log for `CAMERA ON`. If the app shows as `(ignored by config)`, remove it from ignored applications. If nothing is logged at all, run `CameraProbe --test` and check "Camera detection access".
- **Relay or Home Assistant not switching:** run `CameraProbe --test`. A DNS failure means the `.local` name doesn't resolve - use the IP address. Each HTTP call and its status is in the log.
- **"CameraProbe is already running":** only one copy runs at a time. Look in the notification area overflow (**^**).
