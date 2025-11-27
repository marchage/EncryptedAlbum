#!/usr/bin/env bash
set -euo pipefail

# Installs the repo hooks by setting core.hooksPath to .githooks
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

mkdir -p .githooks
cp -f scripts/pre-commit.sh .githooks/pre-commit
chmod +x .githooks/pre-commit

git config core.hooksPath .githooks

echo "Installed git hooks to .githooks and set core.hooksPath." 
