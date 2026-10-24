#!/usr/bin/env bash
# Generates the Android and iOS project folders and adds the network
# permissions the game needs. Run once from the project folder (macOS/Linux).
set -euo pipefail
cd "$(dirname "$0")"

flutter create . --org com.example --project-name coup_lan --platforms android,ios

# --- Android: Wi-Fi / network permissions in the main manifest
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>\n    <application#' "$MANIFEST"
fi
perl -pi -e 's#android:label="coup_lan"#android:label="Coup"#' "$MANIFEST"

# --- iOS: local network permission prompt text + display name
PLIST=ios/Runner/Info.plist
if ! grep -q 'NSLocalNetworkUsageDescription' "$PLIST"; then
  perl -0pi -e 's#</dict>\s*</plist>\s*$#\t<key>NSLocalNetworkUsageDescription</key>\n\t<string>Coup uses your local network to host and join games with nearby players.</string>\n</dict>\n</plist>\n#' "$PLIST"
fi
perl -0pi -e 's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*#${1}Coup#' "$PLIST"

flutter pub get
echo
echo "Done. Connect a phone and run:  flutter run"
