#!/bin/bash
#
# CameraProbe uninstaller
#
# Stops and removes the LaunchAgent, removes the installed app, and
# optionally removes the configuration file.
#
# Run as your normal user - NOT with sudo.

set -euo pipefail

APP_NAME="CameraProbe"
LABEL="com.tim.cameraprobe"
INSTALL_DIR="/Applications/${APP_NAME}"
CONFIG_DIR="/Library/Application Support/${APP_NAME}"
LAUNCH_AGENT_PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

if [[ "${EUID}" -eq 0 ]]; then
    echo "Please run this as your normal user, not with sudo:"
    echo "  ./uninstall.sh"
    exit 1
fi

echo "==> Stopping ${APP_NAME}"
launchctl bootout "gui/${UID}/${LABEL}" 2>/dev/null || true

echo "==> Removing LaunchAgent"
rm -f "${LAUNCH_AGENT_PLIST}"

echo "==> Removing application"
sudo rm -rf "${INSTALL_DIR}"

if [ -d "${CONFIG_DIR}" ]; then
    read -rp "Remove configuration at ${CONFIG_DIR} too? [y/N]: " REMOVE_CONFIG
    if [[ "${REMOVE_CONFIG}" =~ ^[Yy]$ ]]; then
        sudo rm -rf "${CONFIG_DIR}"
        echo "Removed ${CONFIG_DIR}"
    else
        echo "Left ${CONFIG_DIR} in place."
    fi
fi

echo "${APP_NAME} uninstalled."
