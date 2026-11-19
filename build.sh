#!/bin/bash
# Builds Relabel.app with SwiftPM (no Xcode needed) and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Relabel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/RelabelApp" "$APP/Contents/MacOS/Relabel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift Tools/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"

mkdir -p "$HOME/Applications"
pkill -x Relabel 2>/dev/null || true
rm -rf "$HOME/Applications/Relabel.app"
cp -R "$APP" "$HOME/Applications/Relabel.app"
echo "Installed ~/Applications/Relabel.app"
