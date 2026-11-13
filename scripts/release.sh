#!/usr/bin/env bash
# Build a notarized, stapled Developer ID release of Lune.
#
#   scripts/release.sh
#
# Archive (Release) -> export (Developer ID) -> zip -> notarize -> staple -> re-zip.
# Output: ~/Downloads/Lune-<version>/Lune.app and Lune.zip.
#
# Needs: a "Developer ID Application" certificate for team 627Y9R25T5 in the
# login keychain, a notarytool keychain profile named "lune-notary"
# (override with NOTARY_PROFILE), xcodegen, and Lune/Config/Secrets.swift.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
NOTARY_PROFILE=${NOTARY_PROFILE:-lune-notary}
BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/Lune.xcarchive"
EXPORT="$BUILD/export"

if [ ! -f Lune/Config/Secrets.swift ]; then
  echo "Missing Lune/Config/Secrets.swift (copy Secrets.swift.template and fill in Last.fm keys)." >&2
  exit 1
fi
# Check the string values, not the whole file: the setup comment mentions the
# placeholder text too.
for name in apiKey apiSecret; do
  value=$(sed -nE "s/.*static let $name *= *\"([^\"]*)\".*/\1/p" Lune/Config/Secrets.swift | head -n1)
  case "$value" in
    ""|YOUR_*_HERE)
      echo "warning: Secrets.swift has no real Last.fm $name; Last.fm won't work in this build." >&2 ;;
  esac
done

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> Generating project"
xcodegen generate --quiet

echo "==> Archiving"
xcodebuild archive \
  -project Lune.xcodeproj -scheme Lune -configuration Release \
  -archivePath "$ARCHIVE" -destination "generic/platform=macOS" \
  -quiet

echo "==> Exporting (Developer ID)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates -quiet

APP="$EXPORT/Lune.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILDNUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
OUT="$HOME/Downloads/Lune-$VERSION"
echo "==> Lune $VERSION ($BUILDNUM)"

codesign --verify --deep --strict "$APP"

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$BUILD/Lune.zip"
xcrun notarytool submit "$BUILD/Lune.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
  | tee "$BUILD/notarize.log"
if ! grep -q "status: Accepted" "$BUILD/notarize.log"; then
  ID=$(awk '/^  id:/{print $2; exit}' "$BUILD/notarize.log")
  echo "Notarization failed. Log:" >&2
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2
  exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

echo "==> Packaging"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto "$APP" "$OUT/Lune.app"
ditto -c -k --keepParent "$OUT/Lune.app" "$OUT/Lune.zip"
echo "Done: $OUT/Lune.zip"
