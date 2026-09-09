#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SONAR_STAGE=$(mktemp -d /private/tmp/sonarlab-build.XXXXXX)
trap 'rm -rf "$SONAR_STAGE"' EXIT
SONAR_APP="$SONAR_STAGE/Sonar.app"
mkdir -p "$SONAR_APP/Contents/MacOS" "$SONAR_APP/Contents/Resources"
ditto assets/zoom "$SONAR_APP/Contents/Resources/Zoom"
ditto assets/gallery "$SONAR_APP/Contents/Resources/Gallery"
cp assets/sonar.png "$SONAR_APP/Contents/Resources/SonarMark.png"
SONAR_ICONSET="$SONAR_STAGE/Sonar.iconset"
mkdir -p "$SONAR_ICONSET"
swift script/render_icon.swift assets/sonar.png "$SONAR_STAGE/DockIcon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SONAR_STAGE/DockIcon.png" --out "$SONAR_ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SONAR_STAGE/DockIcon.png" --out "$SONAR_ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SONAR_ICONSET" -o "$SONAR_APP/Contents/Resources/Sonar.icns"
# Bundle the reading paper; allow an explicit local replacement.
SONAR_LOCAL_PAPER="${SONAR_PAPER_PATH:-assets/paper/SoundWave.pdf}"
if [[ -f "$SONAR_LOCAL_PAPER" ]]; then
  cp "$SONAR_LOCAL_PAPER" "$SONAR_APP/Contents/Resources/SoundWave.pdf"
elif [[ -n "${SONAR_PAPER_PATH:-}" ]]; then
  echo "PDF not found: $SONAR_PAPER_PATH" >&2
  exit 1
fi
swiftc -O work/SonarLab/main.swift work/SonarLab/HardwareAudio.swift work/SonarLab/SystemScroll.swift work/SonarLab/DemoModes.swift work/SonarLab/WaveCalibration.swift work/SonarLab/ContentView.swift work/SonarLab/ControlModeView.swift work/SonarLab/SignalView.swift work/SonarLab/AudioSignalView.swift work/SonarLab/Distance.swift work/SonarLab/Position.swift work/SonarLab/EchoFlowView.swift work/SonarLab/Zoom.swift -o "$SONAR_APP/Contents/MacOS/SonarLab" -framework AppKit -framework SwiftUI -framework AVFoundation -framework Accelerate -framework CoreAudio -framework PDFKit -framework Carbon -framework ApplicationServices
cat > "$SONAR_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SonarLab</string>
<key>CFBundleIdentifier</key><string>com.emanuel.sonarlab</string>
<key>CFBundleName</key><string>Sonar</string>
<key>CFBundleDisplayName</key><string>Sonar</string>
<key>CFBundleIconFile</key><string>Sonar.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>Sonar listens for reflections of its test tone to detect hand movement. Audio is not saved.</string>
</dict></plist>
PLIST
# A stable certificate preserves permissions across rebuilds. Local builds can
# use ad-hoc signing without owning a paid Apple developer certificate.
SONAR_SIGNING_IDENTITY="${SONAR_SIGNING_IDENTITY:--}"
codesign --force --sign "$SONAR_SIGNING_IDENTITY" --identifier com.emanuel.sonarlab "$SONAR_APP"
codesign --verify --strict "$SONAR_APP"
# Verify the failure path exits normally, then test the staged build. No failed
# test build replaces or stops the user's current installed app.
SONAR_TEST_STATUS=0
"$SONAR_APP/Contents/MacOS/SonarLab" --self-test-failure-probe >"$SONAR_STAGE/failure-probe.log" 2>&1 || SONAR_TEST_STATUS=$?
if [[ "$SONAR_TEST_STATUS" != 1 ]] || ! /usr/bin/grep -q 'Intentional clean-exit probe' "$SONAR_STAGE/failure-probe.log"; then
  cat "$SONAR_STAGE/failure-probe.log"
  echo "Test failure handling did not exit cleanly; keeping the installed app."
  exit 1
fi
"$SONAR_APP/Contents/MacOS/SonarLab" --self-test
mkdir -p outputs
# Replace generated output so an optional PDF from an older build cannot linger.
rm -rf outputs/Sonar.app
ditto --noextattr --norsrc "$SONAR_APP" outputs/Sonar.app
ditto -c -k --keepParent --noextattr outputs/Sonar.app outputs/Sonar.zip
if [[ "${1:-}" == "--build-only" ]]; then
  echo "Built and tested: outputs/Sonar.app"
  exit 0
fi
SONAR_INSTALLED_APP="${SONAR_INSTALL_PATH:-$HOME/Applications/Sonar.app}"
# Do not silently replace a certificate-signed installation with an ad-hoc build.
if [[ -d "$SONAR_INSTALLED_APP" && "$SONAR_SIGNING_IDENTITY" == "-" ]] && codesign -dv "$SONAR_INSTALLED_APP" 2>&1 | /usr/bin/grep -q '^Authority='; then
  echo "Set SONAR_SIGNING_IDENTITY to the existing certificate before replacing this installation."
  exit 1
fi
pkill -x SonarLab >/dev/null 2>&1 || true
mkdir -p "$(dirname "$SONAR_INSTALLED_APP")"
# Save the existing bundle, then install into an empty destination. Merging
# bundles leaves removed resources behind and invalidates the new signature.
SONAR_BACKUP="$(mktemp -d "$(dirname "$SONAR_INSTALLED_APP")/.sonar-backup.XXXXXX")"
if [[ -e "$SONAR_INSTALLED_APP" ]]; then mv "$SONAR_INSTALLED_APP" "$SONAR_BACKUP/Previous.app"; fi
if ! (ditto --noextattr --norsrc "$SONAR_APP" "$SONAR_INSTALLED_APP" &&
      xattr -cr "$SONAR_INSTALLED_APP" && codesign --verify --strict "$SONAR_INSTALLED_APP"); then
  rm -rf "$SONAR_INSTALLED_APP"
  if [[ -e "$SONAR_BACKUP/Previous.app" ]]; then mv "$SONAR_BACKUP/Previous.app" "$SONAR_INSTALLED_APP"; fi
  rmdir "$SONAR_BACKUP"
  exit 1
fi
rm -rf "$SONAR_BACKUP"
if [[ "${1:-}" == "--verify-scroll" || "${1:-}" == "--verify-audio" ]]; then
  open -n "$SONAR_INSTALLED_APP" --args "$1"
else
  open -n "$SONAR_INSTALLED_APP"
fi
if [[ "${1:-}" == "--verify" ]]; then
  sleep 1
  pgrep -x SonarLab
fi
