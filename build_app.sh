#!/bin/zsh
# Builds SamsungRemote.app (release) in the project folder.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=SamsungRemote.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SamsungRemote "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/AppIcon.iconset
swift make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Samsung Remote</string>
  <key>CFBundleIdentifier</key><string>com.local.samsungremote</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>SamsungRemote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Control your Samsung TV on the local network.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
EOF
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP — run with: open $APP"
