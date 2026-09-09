#!/bin/bash
set -euo pipefail
mkdir -p build/strength-screenshots
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"].startswith("iPhone")]
preferred=next((d for d in devices if d["name"] == "iPhone 17 Pro"), devices[0])
print(preferred["udid"])
')
xcodebuild -scheme NOOPiOS -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath build/strength-simulator BUNDLE_ID_PREFIX=com.commanderastern \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  build > "$RUNNER_TEMP/noop-simulator.log" 2>&1 || {
    grep -n 'error:' "$RUNNER_TEMP/noop-simulator.log" | head -30 || true
    tail -n 100 "$RUNNER_TEMP/noop-simulator.log"
    exit 1
  }
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
APP=$(find build/strength-simulator/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '*.app' -type d | head -1)
xcrun simctl install "$DEVICE" "$APP"
xcrun swiftc Tools/personal/check-strength-capture.swift -o "$RUNNER_TEMP/check-strength-capture"
# Full native strength flow; all seeded readings/history are synthetic demo data.
for screen in more home template picker machines custom warmup active rest exercises edit-set settings minimized history progress summary summary-detail summary-plain achievements island; do
  xcrun simctl terminate "$DEVICE" com.commanderastern.noop || true
  xcrun simctl launch --stdout="$RUNNER_TEMP/strength-$screen.stdout" --stderr="$RUNNER_TEMP/strength-$screen.stderr" \
    "$DEVICE" com.commanderastern.noop --demo-screen "strength-$screen" -theme.appearance dark
  rendered=false
  for attempt in 1 2 3 4 5 6; do
    sleep 8
    xcrun simctl io "$DEVICE" screenshot "build/strength-screenshots/$screen.png"
    if "$RUNNER_TEMP/check-strength-capture" "build/strength-screenshots/$screen.png"; then
      rendered=true
      break
    fi
  done
  if [ "$rendered" != true ]; then
    cat "$RUNNER_TEMP/strength-$screen.stdout" "$RUNNER_TEMP/strength-$screen.stderr" || true
    xcrun simctl spawn "$DEVICE" log show --last 1m --predicate 'process == "NOOP" OR process == "Strand"' || true
    echo "The $screen screen did not render within 48 seconds."
    exit 1
  fi
done
# Keep the actual system Live Activity visible while another app is foreground.
# This is a compact Dynamic Island capture, not a composited widget mockup.
xcrun simctl launch "$DEVICE" com.apple.Preferences
sleep 5
xcrun simctl io "$DEVICE" screenshot "build/strength-screenshots/dynamic-island.png"
