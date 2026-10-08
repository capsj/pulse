#!/bin/sh
# Builds Pulse.app into ./build. Run with --install to also copy it to /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=build/Pulse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Pulse "$APP/Contents/MacOS/Pulse"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon.icns "$APP/Contents/Resources/Icon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$1" = "--install" ]; then
    pkill -x Pulse || true
    rm -rf /Applications/Pulse.app
    cp -R "$APP" /Applications/Pulse.app
    open /Applications/Pulse.app
    echo "Installed to /Applications/Pulse.app"
fi
