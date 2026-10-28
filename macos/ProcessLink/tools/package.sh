#!/bin/zsh
# Builds a universal macOS .app and a compressed DMG under dist/.
#
# Usage:
#   tools/package.sh [--version 0.1.0] [--out ../../dist] [--notarize]
#
# Environment:
#   SIGN_IDENTITY   "Developer ID Application: …" (default: ad-hoc "-")
#   BUILD_NUMBER    CFBundleVersion (default: UTC timestamp)
#   APPLE_ID / APPLE_TEAM_ID / APPLE_APP_SPECIFIC_PASSWORD  for --notarize
set -euo pipefail

here=${0:A:h}
repo=${here:h}
version=""
out="$repo/dist"
notarize=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --notarize) notarize=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$version" ]]; then
  version=$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
fi
[[ -n "$version" ]] || version=0.1.0
build="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
identity="${SIGN_IDENTITY:--}"
scratch="${PACKAGE_SCRATCH:-$HOME/Library/Developer/ProcessLink/package}"
mkdir -p "$out"

echo "==> Building ProcessLink $version ($build), arm64 + x86_64"
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --package-path "$repo" \
    --scratch-path "$scratch/$arch" 2>&1 | grep -E "error:" && exit 1 || true
  [[ -x "$scratch/$arch/release/ProcessLink" ]] || { echo "missing $arch binary"; exit 1; }
done

app="$out/ProcessLink.app"
rm -rf "$app" "$out/ProcessLink-$version-macOS-universal.dmg" "$out/ProcessLink-$version-macOS-universal.dmg.sha256"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

lipo -create "$scratch/arm64/release/ProcessLink" "$scratch/x86_64/release/ProcessLink" \
  -output "$app/Contents/MacOS/ProcessLink"
lipo -info "$app/Contents/MacOS/ProcessLink"

sed -e "s/__BUILD__/$build/" "$repo/Info.plist.in" > "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"

if [[ ! -f "$repo/Resources/AppIcon.icns" ]]; then
  "$repo/tools/make_icon.sh"
fi
cp -X "$repo/Resources/AppIcon.icns" "$app/Contents/Resources/"
[[ -f "$repo/Resources/Assets.car" ]] && cp -X "$repo/Resources/Assets.car" "$app/Contents/Resources/"

xattr -cr "$app"
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/ProcessLink.app"
ln -s /Applications "$stage/Applications"

dmg="$out/ProcessLink-$version-macOS-universal.dmg"
hdiutil create -quiet -volname "ProcessLink" -srcfolder "$stage" -ov -format UDZO "$dmg"
shasum -a 256 "$dmg" | awk '{print $1"  '"$(basename "$dmg")"'"}' > "$dmg.sha256"

if [[ $notarize -eq 1 ]]; then
  : "${APPLE_ID:?APPLE_ID is required for --notarize}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for --notarize}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required for --notarize}"
  xcrun notarytool submit "$dmg" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
fi

echo "==> $dmg"
echo "==> $dmg.sha256"
du -h "$dmg" | awk '{print "    "$1}'
