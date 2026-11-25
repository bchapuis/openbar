#!/bin/sh
# Builds build/OpenBar.app. Pass "install" to also copy it to /Applications.
#
# The app bundle carries everything the privileged helper needs:
#   Contents/Resources/local.OpenBar.helper   the helper (root daemon)
#   Contents/Resources/openconnect/                   openconnect and its libraries
set -e
cd "$(dirname "$0")"

LABEL=local.OpenBar.helper
APP=build/OpenBar.app
RES="$APP/Contents/Resources"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
cp Info.plist "$APP/Contents/"
cp "$BIN/OpenBar" "$APP/Contents/MacOS/"
cp "$BIN/OpenBarHelper" "$RES/$LABEL"
cp Resources/* "$RES/"
python3 scripts/bundle_openconnect.py "$RES/openconnect"
codesign --force --sign - --identifier "$LABEL" "$RES/$LABEL"

# The app compares this hash with the installed helper's to know when to update it.
(cd "$RES" && find "$LABEL" "$LABEL.plist" openconnect -type f | sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1) > "$RES/payload-version"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$1" = "install" ]; then
    rm -rf /Applications/OpenBar.app
    cp -R "$APP" /Applications/
    # Make Finder and Spotlight notice the new bundle (and its icon).
    touch /Applications/OpenBar.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/OpenBar.app
    echo "Installed /Applications/OpenBar.app"
fi
