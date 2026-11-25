#!/bin/sh
# Integration test of the privileged helper.
#
# Runs the real helper binary as an unprivileged LaunchAgent, with a fake
# openconnect, and drives it over XPC through the app's command-line mode.
# Nothing is installed system-wide and no VPN is touched: the test uses its
# own copy of the app (with its own bundle identifier and settings), its own
# Mach service name, and a temporary directory.
set -u
cd "$(dirname "$0")/.."

# Always test a fresh build.
./build.sh > /dev/null || { echo "The build failed."; exit 1; }

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DOMAIN=local.OpenBar.test
LABEL="local.OpenBar.helper.test.$$"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/openconnect-test.XXXXXX")"
APP="$WORK/OpenBar Test.app"
CLI="$APP/Contents/MacOS/OpenBar"
ROOT="$WORK/root"
FAILURES=0

cleanup() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2> /dev/null
    defaults delete "$DOMAIN" 2> /dev/null
    "$LSREGISTER" -u "$APP" 2> /dev/null
    rm -rf "${WORK:?}"
}
trap cleanup EXIT

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "$2" | sed 's/^/        /'; FAILURES=$((FAILURES + 1)); }
# expect <description> <text> <pattern>: the text must contain the pattern.
expect() { if echo "$2" | grep -q -- "$3"; then pass "$1"; else fail "$1" "$2"; fi; }
helper() { OPENCONNECT_MENU_TEST_SERVICE="$LABEL" "$CLI" "$@" 2>&1; }
connect() { echo "$1" | helper --helper-connect; }
state() { helper --helper-check | sed -n 's/^state: //p'; }
# wait_for <pattern>: polls the state for up to ten seconds.
wait_for() {
    for _ in $(seq 1 50); do
        state | grep -q -- "$1" && return 0
        sleep 0.2
    done
    return 1
}

# A copy of the app with its own identity, so that the test reads its own
# settings and the helper can pin this exact build.
ditto build/OpenBar.app "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOMAIN" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2> /dev/null
defaults write "$DOMAIN" server vpn.example.com
defaults write "$DOMAIN" user alex@example.com
defaults write "$DOMAIN" protocol gp
defaults write "$DOMAIN" savePassword -bool false

# The helper's root directory: a fake openconnect, and the two files the
# installer normally writes.
mkdir -p "$ROOT/openconnect/bin"
cp Tests/Integration/fake_openconnect.py "$ROOT/openconnect/bin/openconnect"
chmod +x "$ROOT/openconnect/bin/openconnect"
cp "$APP/Contents/Resources/payload-version" "$ROOT/"
printf 'cdhash H"%s"\n' "$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')" > "$ROOT/client-requirement"

cat > "$WORK/agent.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array>
        <string>$APP/Contents/Resources/local.OpenBar.helper</string>
        <string>--root</string><string>$ROOT</string>
        <string>--service</string><string>$LABEL</string>
    </array>
    <key>MachServices</key><dict><key>$LABEL</key><true/></dict>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$WORK/agent.plist" || { echo "Could not start the test helper."; exit 1; }

echo "Helper answers its client"
OUTPUT="$(helper --helper-check)"
expect "reports the payload version of the app" "$OUTPUT" "payload version: $(cat "$ROOT/payload-version")"
expect "starts disconnected" "$OUTPUT" "^state: disconnected"

echo "Helper rejects other programs"
cp "$CLI" "$WORK/other-client"
codesign --force --sign - --identifier other "$WORK/other-client" 2> /dev/null
OUTPUT="$(OPENCONNECT_MENU_TEST_SERVICE="$LABEL" "$WORK/other-client" --helper-check 2>&1)"
expect "refuses a client with another code hash" "$OUTPUT" "helper not reachable"

echo "Connect"
expect "starts openconnect" "$(connect secret)" "^started"
if wait_for "^connected 10.20.30.40"; then pass "reports the tunnel address"; else fail "reports the tunnel address" "$(state)"; fi
LOG="$(helper --helper-check)"
expect "passes the password on standard input, and nothing else" "$LOG" "STDIN password-length=6 extra-bytes=0"
expect "passes the settings" "$LOG" "ARGUMENTS --protocol=gp|--user=alex@example.com|"
expect "quotes the script path" "$LOG" "|--script='$ROOT/openconnect/etc/vpnc-script'|"
expect "puts the server last" "$LOG" "|--passwd-on-stdin|--non-inter|vpn.example.com$"
expect "refuses a second connection" "$(connect secret)" "A connection is already active."

echo "Disconnect"
START=$(date +%s)
expect "replies when openconnect has exited" "$(helper --helper-disconnect)" "^disconnected"
[ $(($(date +%s) - START)) -le 3 ] && pass "is quick" || fail "is quick"
LOG="$(helper --helper-check)"
expect "lets openconnect log off (SIGINT)" "$LOG" "Logout successful."
expect "ends disconnected, without an error" "$LOG" "^state: disconnected  $"

echo "Failures"
connect wrong > /dev/null
if wait_for "^disconnected .*Failed to complete authentication"; then pass "reports why openconnect stopped"
else fail "reports why openconnect stopped" "$(state)"; fi
defaults write "$DOMAIN" extraOptions "--script=/tmp/evil.sh"
expect "refuses an option that is not on the list" "$(connect secret)" "Option not allowed: --script=/tmp/evil.sh"
defaults write "$DOMAIN" extraOptions "--no-dtls"
expect "accepts an option that is on the list" "$(connect secret)" "^started"
wait_for "^connected" > /dev/null
expect "passes the option on" "$(helper --helper-check)" "|--no-dtls|--passwd-on-stdin|"
helper --helper-disconnect > /dev/null
defaults delete "$DOMAIN" extraOptions

echo "An openconnect that ignores SIGINT"
connect stubborn > /dev/null
wait_for "^connected" > /dev/null
START=$(date +%s)
helper --helper-disconnect > /dev/null
ELAPSED=$(($(date +%s) - START))
[ "$ELAPSED" -ge 5 ] && [ "$ELAPSED" -le 9 ] && pass "is terminated after six seconds" || fail "is terminated after six seconds" "took ${ELAPSED}s"
expect "was stopped with SIGTERM" "$(helper --helper-check)" "Terminated."

echo "Helper shutdown"
connect secret > /dev/null
wait_for "^connected" > /dev/null
launchctl bootout "gui/$(id -u)/$LABEL"
sleep 2
if pgrep -f "$ROOT/openconnect/bin/openconnect" > /dev/null; then fail "stops openconnect when the helper is stopped"
else pass "stops openconnect when the helper is stopped"; fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "All helper tests passed."; else echo "$FAILURES helper test(s) failed."; exit 1; fi
