#!/bin/bash
# Build AgentFocus.app helper bundle. Usage: ./build.sh [output-dir]
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/build}"
APP="$OUT/AgentFocus.app"

mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.agentfocus.helper</string>
  <key>CFBundleName</key><string>AgentFocus</string>
  <key>CFBundleExecutable</key><string>AgentFocus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>AgentFocus selects the terminal tab where your agent is waiting.</string>
</dict></plist>
EOF

swiftc "$SRC/main.swift" -O -o "$APP/Contents/MacOS/AgentFocus" \
  -framework Cocoa -framework Carbon -framework ServiceManagement -framework UserNotifications
codesign -f -s - "$APP"
echo "Built $APP"
