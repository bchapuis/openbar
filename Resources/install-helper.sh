#!/bin/sh
# Installs or updates the privileged helper. Must run as root.
# Usage: install-helper.sh <app Resources directory> <code hash of the app>
set -e

RESOURCES="$1"
CDHASH="$2"
LABEL=local.OpenBar.helper
SUPPORT="/Library/Application Support/OpenBar"
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

case "$CDHASH" in
    *[!0-9a-f]* | "") echo "Invalid code hash." >&2; exit 1 ;;
esac

# Stop a previous version. It disconnects the VPN before it exits.
launchctl bootout "system/$LABEL" 2> /dev/null || true

mkdir -p /Library/PrivilegedHelperTools "$SUPPORT"
rm -rf "$SUPPORT/openconnect"
cp -R "$RESOURCES/openconnect" "$SUPPORT/openconnect"
cp "$RESOURCES/payload-version" "$SUPPORT/payload-version"
cp "$RESOURCES/$LABEL" "$HELPER"
cp "$RESOURCES/$LABEL.plist" "$PLIST"
# Only the app that ran this installation may talk to the helper.
printf 'cdhash H"%s"\n' "$CDHASH" > "$SUPPORT/client-requirement"

chown -R root:wheel "$SUPPORT" "$HELPER" "$PLIST"
chmod -R u=rwX,go=rX "$SUPPORT"
chmod 755 "$HELPER"
chmod 644 "$PLIST"

# The old instance may still be shutting down: retry for a few seconds.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if launchctl bootstrap system "$PLIST" 2> /dev/null; then
        echo "Helper installed."
        exit 0
    fi
    sleep 1
done
echo "Could not start the helper (launchctl bootstrap failed)." >&2
exit 1
