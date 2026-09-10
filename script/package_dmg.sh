#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SONAR_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${SONAR_NOTARY_PROFILE:?Set a notarytool keychain profile}"
# Install the layout tool in an isolated environment, then set SONAR_DMGBUILD
# to its bin/dmgbuild executable: python3 -m venv /tmp/sonar-dmg-tools &&
# /tmp/sonar-dmg-tools/bin/pip install dmgbuild==1.6.7
SONAR_DMGBUILD="${SONAR_DMGBUILD:-dmgbuild}"
command -v "$SONAR_DMGBUILD" >/dev/null || { echo "Install dmgbuild and set SONAR_DMGBUILD (see script comments)." >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit source changes before packaging a release." >&2
  exit 1
fi
./script/build_and_run.sh --build-only
SONAR_RELEASE=$(mktemp -d /private/tmp/sonar-release.XXXXXX)
trap 'rm -rf "$SONAR_RELEASE"' EXIT
mkdir -p "$SONAR_RELEASE/image"
ditto --noextattr --norsrc outputs/Sonar.app "$SONAR_RELEASE/image/Sonar.app"
SONAR_BUNDLE="$SONAR_RELEASE/image/Sonar.app"
SONAR_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SONAR_BUNDLE/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Add :SonarSourceRevision string $(git rev-parse HEAD)" "$SONAR_BUNDLE/Contents/Info.plist"
xattr -cr "$SONAR_BUNDLE"
codesign --force --options runtime --timestamp --entitlements script/Sonar.entitlements --sign "$SONAR_SIGNING_IDENTITY" "$SONAR_BUNDLE"
codesign --verify --strict "$SONAR_BUNDLE"
ditto -c -k --keepParent "$SONAR_BUNDLE" "$SONAR_RELEASE/Sonar.zip"
xcrun notarytool submit "$SONAR_RELEASE/Sonar.zip" --keychain-profile "$SONAR_NOTARY_PROFILE" --wait
xcrun stapler staple "$SONAR_BUNDLE"
xcrun stapler validate "$SONAR_BUNDLE"
spctl --assess --type execute --verbose=2 "$SONAR_BUNDLE"
swift script/render_dmg_background.swift "$SONAR_RELEASE/background.png"
SONAR_DMG="outputs/Sonar-${SONAR_VERSION}-$(uname -m).dmg"
"$SONAR_DMGBUILD" -s script/dmg_settings.py -D "app=$SONAR_BUNDLE" -D "background=$SONAR_RELEASE/background.png" Sonar "$SONAR_DMG"
codesign --timestamp --sign "$SONAR_SIGNING_IDENTITY" "$SONAR_DMG"
xcrun notarytool submit "$SONAR_DMG" --keychain-profile "$SONAR_NOTARY_PROFILE" --wait
xcrun stapler staple "$SONAR_DMG"
xcrun stapler validate "$SONAR_DMG"
hdiutil verify "$SONAR_DMG"
echo "Ready: $SONAR_DMG"
