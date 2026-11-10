#!/bin/zsh
# Builds Overview.app into ./build with an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Overview"

APP="build/Overview.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Overview"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signatures default to a cdhash designated requirement, which changes on
# every build and invalidates privacy grants (Accessibility, Calendars). Pin the
# designated requirement to the bundle identifier so grants survive rebuilds.
codesign --force --sign - --identifier com.bamfhealth.overview \
  --requirements '=designated => identifier "com.bamfhealth.overview"' "$APP"

echo "Built $APP"
