#!/bin/bash
#
# CameraProbe installer
#
# Builds the release binary, installs it to /Applications/CameraProbe,
# writes (or preserves) /Library/Application Support/CameraProbe/config.json,
# installs a LaunchAgent so it starts automatically, and does a basic
# reachability check against the configured relay and Home Assistant hosts.
#
# Run as your normal user - NOT with sudo. It asks for your password
# only for the specific steps that need elevated access.

set -euo pipefail

APP_NAME="CameraProbe"
LABEL="com.tim.cameraprobe"
INSTALL_DIR="/Applications/${APP_NAME}"
CONFIG_DIR="/Library/Application Support/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.json"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="${LAUNCH_AGENT_DIR}/${LABEL}.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -eq 0 ]]; then
    echo "Please run this as your normal user, not with sudo:"
    echo "  ./install.sh"
    echo "It will prompt for your password only when it needs elevated access."
    exit 1
fi

echo "==> Building ${APP_NAME} (release)"
cd "${SCRIPT_DIR}"
swift build -c release

BINARY_PATH="${SCRIPT_DIR}/.build/release/${APP_NAME}"
if [ ! -f "${BINARY_PATH}" ]; then
    echo "Build failed: ${BINARY_PATH} not found."
    exit 1
fi

echo "==> Installing binary to ${INSTALL_DIR}"
sudo mkdir -p "${INSTALL_DIR}"
sudo cp "${BINARY_PATH}" "${INSTALL_DIR}/${APP_NAME}"
sudo chmod 755 "${INSTALL_DIR}/${APP_NAME}"

# SwiftPM release builds are ad-hoc signed with a signature that changes
# on every rebuild. macOS ties privacy permissions (like the Local
# Network prompt you approve for .local/mDNS access) to that identity,
# so without a stable identifier here, every reinstall after a code
# change would re-prompt for Local Network access. Re-signing with a
# fixed --identifier gives TCC something consistent to remember.
echo "==> Code-signing binary with a stable identifier"
sudo codesign --force --sign - --identifier "${LABEL}" "${INSTALL_DIR}/${APP_NAME}"

echo "==> Setting up configuration"
sudo mkdir -p "${CONFIG_DIR}"

if [ -f "${CONFIG_FILE}" ]; then
    echo "Existing config found at ${CONFIG_FILE} - leaving it untouched."
else
    read -rp "Relay hostname [onair.local]: " RELAY_HOST
    RELAY_HOST=${RELAY_HOST:-onair.local}

    read -rp "Relay port [80]: " RELAY_PORT
    RELAY_PORT=${RELAY_PORT:-80}

    read -rp "Home Assistant hostname [homeassistant.local]: " HA_HOST
    HA_HOST=${HA_HOST:-homeassistant.local}

    read -rp "Home Assistant port [8123]: " HA_PORT
    HA_PORT=${HA_PORT:-8123}

    CONFIG_JSON=$(cat <<EOF
{
  "relay": {
    "enabled": true,
    "host": "${RELAY_HOST}",
    "port": ${RELAY_PORT}
  },
  "homeAssistant": {
    "enabled": true,
    "host": "${HA_HOST}",
    "port": ${HA_PORT}
  }
}
EOF
)
    echo "${CONFIG_JSON}" | sudo tee "${CONFIG_FILE}" > /dev/null
    sudo chmod 644 "${CONFIG_FILE}"
    echo "Wrote ${CONFIG_FILE}"
fi

echo "==> Installing LaunchAgent"
mkdir -p "${LAUNCH_AGENT_DIR}"
sed "s|__BINARY_PATH__|${INSTALL_DIR}/${APP_NAME}|g; s|__LABEL__|${LABEL}|g" \
    "${SCRIPT_DIR}/${LABEL}.plist.template" > "${LAUNCH_AGENT_PLIST}"

launchctl bootout "gui/${UID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${UID}" "${LAUNCH_AGENT_PLIST}"
launchctl enable "gui/${UID}/${LABEL}"

echo "==> Verifying connectivity"

extract_json_value() {
    local file="$1" section="$2" key="$3" default="$4"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$file" "$section" "$key" "$default" <<'PYEOF'
import json, sys
file, section, key, default = sys.argv[1:5]
try:
    with open(file) as f:
        data = json.load(f)
    print(data.get(section, {}).get(key, default))
except Exception:
    print(default)
PYEOF
    else
        echo "${default}"
    fi
}

RELAY_CHECK_HOST=$(extract_json_value "${CONFIG_FILE}" relay host onair.local)
RELAY_CHECK_PORT=$(extract_json_value "${CONFIG_FILE}" relay port 80)
HA_CHECK_HOST=$(extract_json_value "${CONFIG_FILE}" homeAssistant host homeassistant.local)
HA_CHECK_PORT=$(extract_json_value "${CONFIG_FILE}" homeAssistant port 8123)

check_connectivity() {
    local label="$1" host="$2" port="$3"

    # .local hostnames go through mDNS, which can be slow to answer on a
    # completely cold lookup. Give the resolver a head start so the timed
    # curl check below isn't racing a first-ever mDNS query.
    ping -c 1 -t 2 "${host}" >/dev/null 2>&1 || true

    # -4 forces IPv4: curl (unlike URLSession, which races v4/v6 via Happy
    # Eyeballs) can stall waiting on an IPv6 attempt before falling back,
    # which is enough on its own to blow past a short timeout even though
    # the host is reachable over IPv4.
    if curl -4 -s -o /dev/null --connect-timeout 5 --max-time 8 "http://${host}:${port}/" 2>/dev/null; then
        printf "  %-16s OK\n" "${label}"
    else
        printf "  %-16s UNREACHABLE (check hostname/network)\n" "${label}"
    fi
}

check_connectivity "Relay" "${RELAY_CHECK_HOST}" "${RELAY_CHECK_PORT}"
check_connectivity "Home Assistant" "${HA_CHECK_HOST}" "${HA_CHECK_PORT}"

echo ""
echo "${APP_NAME} installed and running."
echo "Config:  ${CONFIG_FILE}"
echo "Logs:    log stream --predicate 'subsystem == \"${LABEL}\"'"
echo "Restart: launchctl kickstart -k gui/${UID}/${LABEL}"
echo "Remove:  ./uninstall.sh"
