# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
