#!/bin/sh
# Build dist/NoteHero.app. Signs ad hoc unless NOTEHERO_SIGN_IDENTITY is set.
#
#   scripts/build.sh              # dist/NoteHero.app
#   scripts/build.sh --dmg        # also dist/notehero-<version>.dmg
#   scripts/build.sh --notarize   # --dmg, then notarize and staple it, and zip the
#                                 # stapled app as dist/notehero-<version>-macos-arm64.zip
#                                 # (needs NOTEHERO_NOTARY_PROFILE)
set -eu
cd "$(dirname "$0")/.."

DMG=0; NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --dmg) DMG=1 ;;
    --notarize) DMG=1; NOTARIZE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
APP=dist/NoteHero.app
IDENTITY=${NOTEHERO_SIGN_IDENTITY:--}

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/NoteHero

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NoteHero"
cp Info.plist "$APP/Contents/Info.plist"

# AppIcon.icns from the 1024px icon.png
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "built $APP ($VERSION)"

if [ "$DMG" = 1 ]; then
  DMGFILE=dist/notehero-$VERSION.dmg
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMGFILE"
  hdiutil create -volname NoteHero -srcfolder "$STAGE" -format UDZO -quiet "$DMGFILE"
  [ "$IDENTITY" = "-" ] || codesign --force --timestamp --sign "$IDENTITY" "$DMGFILE"
  echo "built $DMGFILE"
fi

if [ "$NOTARIZE" = 1 ]; then
  : "${NOTEHERO_NOTARY_PROFILE:?set NOTEHERO_NOTARY_PROFILE to a notarytool keychain profile}"
  xcrun notarytool submit "$DMGFILE" --keychain-profile "$NOTEHERO_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMGFILE"
  # the app inside was notarized with the dmg; staple its ticket for the zip
  xcrun stapler staple "$APP"
  ZIP=dist/notehero-$VERSION-macos-arm64.zip
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "notarized $DMGFILE and $ZIP"
fi
