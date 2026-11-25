#!/bin/sh
# Runs the unit tests, then (with "all") the helper integration test.
#
# The tests use Swift Testing. Xcode provides it out of the box; with only the
# Command Line Tools installed, the compiler must be told where it is.
set -e
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
elif [ -d "$CLT/Frameworks/Testing.framework" ]; then
    swift test \
        -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
        -Xlinker -F -Xlinker "$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/usr/lib"
else
    swift test
fi

if [ "$1" = "all" ]; then
    scripts/test_helper.sh
fi
