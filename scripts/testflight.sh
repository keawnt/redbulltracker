#!/bin/zsh
# Archive CanCount and push it to TestFlight.
#
# Prereqs (one-time):
#   1. Paid Apple Developer Program membership.
#   2. Team set: either `export CANCOUNT_TEAM_ID=XXXXXXXXXX && xcodegen generate`
#      or pick the Team once in Xcode → Signing & Capabilities.
#   3. An app record in App Store Connect with bundle id com.keawn.cancount
#      (App Store Connect → Apps → + → New App).
#   4. Signed in to Xcode with your Apple ID (Xcode → Settings → Accounts).
#
# Then:  ./scripts/testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="build/CanCount.xcarchive"

xcodegen generate

xcodebuild archive \
  -project CanCount.xcodeproj \
  -scheme CanCount \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates

echo "Uploaded. App Store Connect will email you when the build finishes processing (~10 min)."
echo "Then: App Store Connect → TestFlight → add testers or create a public link."
