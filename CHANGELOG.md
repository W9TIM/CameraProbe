# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

- **Windows version (0.1.0 preview)** in `windows/` - a C#/.NET 8 tray app with the same behavior as the macOS app: relay + Home Assistant notifications, tray icon with a red tally light while the camera is in use, Inactivate/Reactivate, Preferences window, Start at Login, splash screen, and the `--test`/`--status`/`--version`/`--help` CLI. Same config schema, at `%APPDATA%\CameraProbe\config.json`. Per-user Inno Setup installer (`windows\build-installer.ps1`). See `windows/README.md`.
- Windows-specific behavior: the app using the camera is identified directly (no 3-second frontmost-app delay); the camera only counts as off after staying off for 2 seconds, so browsers restarting the stream don't flicker the relay; and quitting or signing out during a session sends the matching "off" first.

## [2.0.0] - 2026-09-19

### Added

- Rewritten as a menu bar app (AppKit): a custom tally-light status icon with a right-click menu for About, Preferences, Inactivate/Reactivate, and Quit. A brief splash screen (showing the same icon) appears on launch.
- **Custom app icon** - a tally-light design (camera lens, glowing red indicator, "ON AIR" badge). Source lives in `Resources/AppIcon.svg`/`Resources/AppIcon.iconset/`; `build-app.sh` compiles it into `AppIcon.icns` via `iconutil` and embeds it in the app bundle, and also sets it as `dist/CameraProbe.dmg`'s volume icon.
- **Menu bar activity dot** - a red circle overlaid directly on the camera icon (not appended text) that lights up the instant CameraProbe detects the camera in use by an application not in `ignoredApplications`, and goes dark the instant it's released or Inactivate is switched on. It's driven entirely by CameraProbe's own local detection - independent of the relay and Home Assistant, and unaffected by whether those integrations are enabled, configured, or reachable.
- **Preferences window** - edit relay enabled/host/port, Home Assistant enabled/host/port, ignored applications, and Start at Login from a dialog instead of hand-editing `config.json`. Saving applies changes immediately, no restart.
- **Inactivate/Reactivate** - pauses relay and Home Assistant notifications from the menu bar without quitting the app; camera detection keeps running underneath.
- **Start at Login**, via `ServiceManagement`/`SMAppService` - replaces the LaunchAgent. Toggled from Preferences.
- `build-app.sh` - assembles a proper `CameraProbe.app` bundle (with `Info.plist`) and a `CameraProbe.dmg`, code-signed with a stable identifier. Install is now drag-`CameraProbe.app`-to-`/Applications`; uninstall is drag-to-Trash. No `sudo`, no installer script, no LaunchAgent.
- Config file moved to a per-user path, `~/Library/Application Support/CameraProbe/config.json` (previously system-wide under `/Library/Application Support/`), so both reading and writing it never require elevated privileges.
- CLI flags (`--test`, `--status`, `--version`, `--help`) are preserved for scripting/troubleshooting from Terminal even though this is now a GUI app.

### Changed

- `--test`/`--status` now report Start at Login status and whether CameraProbe is currently running, instead of querying LaunchAgent state via `launchctl`.

### Migration notes

- Existing installs using the old LaunchAgent should remove it first - see the note at the top of `INSTALL.md`.
- `install.sh`, `uninstall.sh`, and `com.tim.cameraprobe.plist.template` are superseded by `build-app.sh` and kept only for reference during the transition.

## [1.1.0] - 2026-07-30

### Added

- `ignoredApplications` config option - an exclude list of app names (e.g. `["Photo Booth"]`) that never trigger a relay/Home Assistant notification, for privacy or gameplay-capture apps. Matching is case-insensitive. Empty by default, so out of the box every app still notifies, unchanged from 1.0.0.
- ESP8266 relay firmware (`firmware/`) and Home Assistant automation setup docs (`homeassistant/`), for a complete end-to-end reference setup.

## [1.0.0] - 2026-07-30

### Added

- Modular Swift source: `Configuration`, `Logger`, `Relay`, `HomeAssistant`, `ActiveApplication`, `CameraMonitor`, `Diagnostics`, `Utilities`, `main` - each with a single responsibility, replacing the original single-file implementation.
- JSON configuration file at `/Library/Application Support/CameraProbe/config.json`. Relay host/port, Home Assistant host/port, and enabled flags for each are now configurable without recompiling. A malformed or missing config falls back to built-in defaults.
- `install.sh` - builds the release binary, installs it to `/Applications/CameraProbe`, writes the config file (prompting for hostnames on first install only), installs and loads a LaunchAgent, code-signs the binary with a stable identifier so macOS's Local Network permission persists across rebuilds, and runs a connectivity check against both configured endpoints.
- `uninstall.sh` - stops and unloads the LaunchAgent, removes the installed app, and optionally removes the configuration.
- `CameraProbe --test` - runs diagnostics: DNS resolution for both hosts, relay reachability, Home Assistant reachability, `log stream` access, and LaunchAgent status. Exits non-zero if anything fails, so it's scriptable.
- `CameraProbe --status` - one-shot summary of relay, Home Assistant, LaunchAgent, and whether the camera monitor is currently running.
- `CameraProbe --version` / `CameraProbe --help`.

### Fixed

Issues found and fixed while refactoring the original working prototype:

- A race condition where the camera turning off during the 3-second "which app is frontmost" detection window could still fire a stale "camera on" event.
- Unsynchronized shared state between the log-stream callback (background queue) and the main queue - now protected with locks (`CameraState`, `CameraMonitorService`).
- Log stream parsing matched on raw chunks from `availableData`, so a start/stop marker split across two reads could be missed. Now buffered and split on complete lines.
- No recovery if the underlying `log stream` subprocess died; it now restarts automatically with exponential backoff.
- No graceful shutdown - SIGINT/SIGTERM are now handled so the log-stream subprocess and LaunchAgent state are left clean on exit.
- Inconsistent logging between the relay and Home Assistant integrations (one printed to the terminal, the other only logged to the unified logging system) made it look like Home Assistant calls were failing silently when they weren't.
