#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="T1.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc T1Controller.swift -framework Cocoa -framework SwiftUI -framework IOKit -O -o "$APP/Contents/MacOS/T1"
cp Info.plist "$APP/Contents/Info.plist"
cp remote-front.png remote-back.png AppIcon.icns "$APP/Contents/Resources/"
if [ "${SIGN_IDENTITY:-}" != "" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
elif security find-identity -v -p codesigning | grep -q "T1 Developer"; then
    codesign --force --deep --sign "T1 Developer" "$APP"
elif security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | awk -F '"' '{print $2}')
    codesign --force --deep --sign "$DEV_ID" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi
cp "$APP/Contents/MacOS/T1" T1Controller
echo "packed $APP and updated T1Controller"
