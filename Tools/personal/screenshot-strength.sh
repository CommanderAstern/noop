#!/bin/bash
set -euo pipefail
mkdir -p build/strength-screenshots
xcodebuild -scheme NOOPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/strength-simulator BUNDLE_ID_PREFIX=com.commanderastern \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  build > "$RUNNER_TEMP/noop-simulator.log" 2>&1 || {
    tail -n 100 "$RUNNER_TEMP/noop-simulator.log"
    exit 1
  }
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"].startswith("iPhone")]
preferred=next((d for d in devices if d["name"] == "iPhone 17 Pro"), devices[0])
print(preferred["udid"])
')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
APP=$(find build/strength-simulator/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '*.app' -type d | head -1)
xcrun simctl install "$DEVICE" "$APP"
for screen in home active picker history; do
  xcrun simctl terminate "$DEVICE" com.commanderastern.noop || true
  xcrun simctl launch "$DEVICE" com.commanderastern.noop --demo-screen "strength-$screen" -theme.appearance dark
  sleep 8
  xcrun simctl io "$DEVICE" screenshot "build/strength-screenshots/$screen.png"
done
