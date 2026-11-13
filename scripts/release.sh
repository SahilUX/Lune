#!/usr/bin/env bash
# Build a notarized, stapled Developer ID DMG of Lune.
#
#   scripts/release.sh
#
# Archive (Release) -> export (Developer ID) -> DMG (app + /Applications link,
# UDZO, volume "Lune") -> codesign DMG -> notarize DMG -> staple DMG.
# Output: ~/Downloads/Lune-<version>/Lune-<version>.dmg (nothing else).
#
# Needs: a "Developer ID Application" certificate for team 627Y9R25T5 in the
# login keychain, a notarytool keychain profile named "lune-notary"
# (override with NOTARY_PROFILE), xcodegen, and Lune/Config/Secrets.swift.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
NOTARY_PROFILE=${NOTARY_PROFILE:-lune-notary}
TEAM_ID=627Y9R25T5
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

# Pick the Developer ID identity by team, and fail unless exactly one matches.
IDENTITIES=$(security find-identity -v -p codesigning \
  | grep -E "\"Developer ID Application: .*\($TEAM_ID\)\"" || true)
if [ "$(printf '%s\n' "$IDENTITIES" | grep -c .)" -ne 1 ]; then
  echo "Need exactly one Developer ID Application identity for team $TEAM_ID, found:" >&2
  echo "${IDENTITIES:-  (none)}" >&2
  exit 1
fi
IDENTITY=$(printf '%s\n' "$IDENTITIES" | awk '{print $2}')

DMG_NAME="Lune-$VERSION.dmg"
DMG="$BUILD/$DMG_NAME"

echo "==> Building $DMG_NAME"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Lune.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Lune -srcfolder "$STAGE" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$DMG" -quiet

echo "==> Signing DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict "$DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
  | tee "$BUILD/notarize.log"
if ! grep -q "status: Accepted" "$BUILD/notarize.log"; then
  ID=$(awk '/^  id:/{print $2; exit}' "$BUILD/notarize.log")
  echo "Notarization failed. Log:" >&2
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2
  exit 1
fi

echo "==> Stapling DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vvv -t open --context context:primary-signature "$DMG"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$DMG" "$OUT/$DMG_NAME"
echo "Done: $OUT/$DMG_NAME"
