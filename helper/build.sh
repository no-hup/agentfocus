#!/bin/bash
# Build AgentFocus.app helper bundle. Usage: ./build.sh [output-dir]
#
# The artifact is SHIPPED (npm `prepack` builds it into libexec/), not just built
# locally, so two things are not optional:
#   - universal arm64 + x86_64, or Intel Macs get nothing;
#   - an explicit macOS 13 deployment target. Without -target, swiftc stamps the
#     BUILD machine's OS as `minos`, and LaunchServices refuses to launch a binary
#     whose minimum exceeds the running OS — a helper built here (macOS 26) would
#     be dead on every Mac older than the one that built it.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/build}"
APP="$OUT/AgentFocus.app"
BIN="$APP/Contents/MacOS/AgentFocus"
# Single source of truth for the version; the plist used to hardcode 1.0.0 while
# package.json said something else.
VER="$(node -p "require('$SRC/../package.json').version" 2>/dev/null || echo 0.0.0)"

mkdir -p "$APP/Contents/MacOS"
# Unquoted EOF: $VER must expand. The plist contains no other shell metacharacter.
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.agentfocus.helper</string>
  <key>CFBundleName</key><string>AgentFocus</string>
  <key>CFBundleExecutable</key><string>AgentFocus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>AgentFocus selects the terminal tab where your agent is waiting.</string>
</dict></plist>
EOF

for ARCH in arm64 x86_64; do
  swiftc "$SRC/main.swift" -O -target "$ARCH-apple-macos13.0" -o "$BIN.$ARCH" \
    -framework Cocoa -framework Carbon -framework ServiceManagement \
    -framework UserNotifications -framework IOKit
done
lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"
rm -f "$BIN.arm64" "$BIN.x86_64"
# Ad-hoc: valid anywhere, it just carries no Developer ID. Gatekeeper only
# assesses bundles carrying com.apple.quarantine, which npm/curl never set.
codesign -f -s - "$APP"
echo "Built $APP ($VER, $(lipo -archs "$BIN"))"
