#!/usr/bin/env bash
set -euo pipefail

# Quick test helper for verifying your App Group ImportInbox on macOS.
# Usage:
#   1) Run this locally after you've added the App Group to Xcode and run the extension once.
#   2) It creates (if needed) the ImportInbox folder and writes a small test file so the main app
#      can pick it up like a real share.

APP_GROUP_ID="group.biz.front-end.EncryptedAlbum.shared"
CONTAINER="$HOME/Library/Group Containers/$APP_GROUP_ID/ImportInbox"

mkdir -p "$CONTAINER"

TEST_FILE="$CONTAINER/test-share-$(date +%s).txt"
echo "Test share from $(whoami) at $(date)" > "$TEST_FILE"

echo "Wrote test file: $TEST_FILE"
echo
ls -la "$CONTAINER"
