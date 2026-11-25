#!/bin/sh
# Removes the privileged helper and its files. Must run as root.
LABEL=local.OpenBar.helper

launchctl bootout "system/$LABEL" 2> /dev/null
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"
rm -rf "/Library/Application Support/OpenBar"
echo "Helper removed."
