#!/bin/bash
#
# Builds CameraProbe.app - a self-contained app bundle you install by
# dragging it to /Applications, and uninstall by dragging it to the
# Trash. No sudo, no installer, no LaunchAgent.
#
# Run this instead of install.sh. install.sh/uninstall.sh are the old
# LaunchAgent-based flow and are kept only for reference during the
# transition - they are not needed with this app bundle.
#
# Output: dist/CameraProbe.app (and dist/CameraProbe.dmg for easy sharing)

set -euo pipefail

APP_NAME="CameraProbe"
LABEL="com.tim.cameraprobe"
VERSION=$(grep -m1 'let appVersion' Sources/CameraProbe/Configuration.swift | sed -E 's/.*"([^"]+)".*/\1/')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

if [[ "${EUID}" -eq 0 ]]; then
    echo "Please run this as your normal user, not with sudo:"
    echo "  ./build-app.sh"
    exit 1
fi

echo "==> Building ${APP_NAME} ${VERSION} (release)"
cd "${SCRIPT_DIR}"
swift build -c release

BINARY_PATH="${SCRIPT_DIR}/.build/release/${APP_NAME}"
if [ ! -f "${BINARY_PATH}" ]; then
    echo "Build failed: ${BINARY_PATH} not found."
    exit 1
fi

echo "==> Assembling ${APP_NAME}.app"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod 755 "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

sed "s|__LABEL__|${LABEL}|g; s|__VERSION__|${VERSION}|g" \
    "${SCRIPT_DIR}/Info.plist.template" > "${APP_BUNDLE}/Contents/Info.plist"

# App icon: Resources/AppIcon.iconset holds the source PNGs (all sizes
# Apple expects); iconutil (part of Xcode) compiles that into the single
# .icns file the app bundle actually uses. Regenerate the iconset (e.g.
# from Resources/AppIcon.svg) any time the artwork changes - this script
# just compiles whatever's currently in the iconset folder.
ICONSET="${SCRIPT_DIR}/Resources/AppIcon.iconset"
ICNS_PATH="${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
if [ -d "${ICONSET}" ] && command -v iconutil >/dev/null 2>&1; then
    echo "==> Compiling app icon"
    iconutil -c icns "${ICONSET}" -o "${ICNS_PATH}"
else
    echo "==> Skipping app icon (no Resources/AppIcon.iconset or iconutil unavailable) - app will use the default icon"
fi

# Ad-hoc sign with a stable identifier. SwiftPM's own ad-hoc signature
# changes on every rebuild, and macOS ties privacy permissions (Local
# Network, the .local/mDNS prompt) to the signing identity - without a
# fixed --identifier here, every rebuild would re-prompt for permission.
echo "==> Code-signing with a stable identifier"
codesign --force --deep --sign - --identifier "${LABEL}" "${APP_BUNDLE}"

echo "==> Verifying app bundle"
codesign --verify --verbose "${APP_BUNDLE}"

# A DMG with a symlink to /Applications is the standard "drag the icon
# over" install experience - optional, skipped if hdiutil is unavailable
# for some reason, since the .app itself is already fully usable on its
# own.
if command -v hdiutil >/dev/null 2>&1; then
    echo "==> Building ${APP_NAME}.dmg"
    DMG_STAGING="$(mktemp -d)"
    cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
    ln -s /Applications "${DMG_STAGING}/Applications"

    if [ -f "${ICNS_PATH}" ]; then
        cp "${ICNS_PATH}" "${DMG_STAGING}/.VolumeIcon.icns"
    fi

    rm -f "${DIST_DIR}/${APP_NAME}.dmg"
    TMP_DMG="$(mktemp -u "${DIST_DIR}/tmp-XXXXXX").dmg"

    # Built read-write first so the volume icon can be set while it's
    # mounted, then converted to a compressed read-only .dmg for
    # distribution - a plain UDZO can't be modified after creation.
    hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDRW -fs HFS+ "${TMP_DMG}" >/dev/null

    if [ -f "${DMG_STAGING}/.VolumeIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
        MOUNT_DIR="$(mktemp -d)"
        hdiutil attach "${TMP_DMG}" -mountpoint "${MOUNT_DIR}" -nobrowse -quiet
        SetFile -c icnC -a C "${MOUNT_DIR}/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "${MOUNT_DIR}" 2>/dev/null || true
        hdiutil detach "${MOUNT_DIR}" -quiet
        rmdir "${MOUNT_DIR}" 2>/dev/null || true
    elif [ -f "${DMG_STAGING}/.VolumeIcon.icns" ]; then
        echo "  (SetFile not found - .dmg will use the default disk icon; CameraProbe.app itself still has the custom icon)"
        echo "  Get SetFile from Apple's 'Additional Tools for Xcode' download if you want the disk icon too."
    fi

    hdiutil convert "${TMP_DMG}" -format UDZO -ov -o "${DIST_DIR}/${APP_NAME}.dmg" >/dev/null
    rm -f "${TMP_DMG}"
    rm -rf "${DMG_STAGING}"
fi

echo ""
echo "${APP_NAME} ${VERSION} built."
echo ""
echo "To install: drag ${APP_BUNDLE} to /Applications (or open dist/${APP_NAME}.dmg and drag it there)."
echo "To uninstall: drag CameraProbe.app from /Applications to the Trash."
echo ""
echo "First launch: right-click the app and choose Open the first time,"
echo "since it isn't notarized by Apple - after that, opening it normally works."
echo "The first launch will also prompt for Local Network access; approve it"
echo "so the relay and Home Assistant hosts can be reached."
