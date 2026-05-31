#!/bin/bash
# Builds Musy.app — a double-clickable, terminal-free background widget.
set -e
cd "$(dirname "$0")"

APP="Musy.app"
echo "Compiling…"
swiftc Musy.swift -O -o musy

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp musy "$APP/Contents/MacOS/Musy"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>Musy</string>
    <key>CFBundleDisplayName</key>           <string>Musy</string>
    <key>CFBundleIdentifier</key>            <string>com.manya.musy</string>
    <key>CFBundleExecutable</key>            <string>Musy</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>26.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSAppleEventsUsageDescription</key> <string>Musy reads the currently playing track from Spotify.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS gives the app a stable identity (keeps the Spotify
# automation permission from re-prompting on every launch).
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Done → $PWD/$APP"
