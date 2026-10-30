#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../macos/ProcessLink"
APP="dist/ProcessLink.app"
ZIP="dist/ProcessLink-notarize.zip"
: "${DEVELOPER_ID:?Set DEVELOPER_ID (Developer ID Application identity)}"
: "${TEAM_ID:?Set TEAM_ID}"
[[ -d "$APP" ]] || { echo "Build the app first" >&2; exit 2; }
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
else
  : "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}"
  : "${APP_PASSWORD:?Set APP_PASSWORD or NOTARY_PROFILE}"
  xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
fi
xcrun stapler staple "$APP"
spctl -a -vv "$APP"
