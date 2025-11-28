#!/usr/bin/env bash
# Refresh provisioning profiles and trigger Xcode to re-create profiles for the project
# WARNING: This runs xcodebuild with -allowProvisioningUpdates which will attempt to
# update or create provisioning profiles for your Apple ID — you must be signed in to
# Xcode with an Apple Developer account that has permission to create profiles.

set -euo pipefail

# Support a dry-run mode so you can preview actions without making changes.
DRY_RUN=0
if [[ "${1-}" == "--dry-run" || "${DRY_RUN_ENV-}" == "1" ]]; then
  DRY_RUN=1
  echo "*** DRY-RUN mode: no files will be removed and xcodebuild will not be executed"
fi

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

echo "This script will:"
echo "  1) Remove locally-cached provisioning profiles (you may want to back them up first)"
echo "  2) Run xcodebuild for the iOS scheme with -allowProvisioningUpdates to prompt Xcode to recreate any missing profiles"
echo
read -p "Proceed? (y/N) " -r PROCEED
if [[ "$PROCEED" != "y" && "$PROCEED" != "Y" ]]; then
  echo "Aborting."
  exit 0
fi

echo "Backing up existing profiles to ~/Desktop/provisioning-backup/"
mkdir -p ~/Desktop/provisioning-backup/
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY-RUN] cp -v ~/Library/MobileDevice/Provisioning Profiles/* ~/Desktop/provisioning-backup/"
else
  cp -v ~/Library/MobileDevice/Provisioning\ Profiles/* ~/Desktop/provisioning-backup/ 2>/dev/null || true
fi

echo "Removing all local provisioning profiles (requires your agreement)…"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY-RUN] rm -f ~/Library/MobileDevice/Provisioning Profiles/*"
else
  rm -f ~/Library/MobileDevice/Provisioning\ Profiles/* || true
fi

echo "Running xcodebuild to allow provisioning updates — this will trigger Xcode to create/update profiles if possible"
echo "(Make sure Xcode is signed in to your Apple ID with a team that has permissions)"

# Use the actual scheme name from the project (list available with xcodebuild -list)
SCHEME="iOS Debug"
PROJECT_FILE="EncryptedAlbum.xcodeproj"

echo "Attempting xcodebuild - allow provisioning updates for scheme: $SCHEME"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY-RUN] xcodebuild -project \"$PROJECT_FILE\" -scheme \"$SCHEME\" -destination 'platform=iOS Simulator,name=iPhone 14,OS=latest' clean build -allowProvisioningUpdates"
else
  xcodebuild -project "$PROJECT_FILE" -scheme "$SCHEME" -destination 'platform=iOS Simulator,name=iPhone 14,OS=latest' clean build -allowProvisioningUpdates
fi

echo "xcodebuild finished. If signing still fails for device builds, try to open the project in Xcode (GUI) and inspect the Signing & Capabilities section for each target."
echo "If the extension or app still isn't signed right, you'll need to make sure App IDs and App Groups are enabled on developer.apple.com and regenerate provisioning profiles for the App ID(s)."

echo "Done."
