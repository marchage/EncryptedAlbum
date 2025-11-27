#!/usr/bin/env bash
set -euo pipefail

# Run repository safety checks before committing.
# This script should be installed as .git/hooks/pre-commit or used via core.hooksPath.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

echo "Running repository safety checks: check-no-prints + swiftlint"

bash ./scripts/check-no-prints.sh

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --config .swiftlint.yml
else
  echo "swiftlint not found, skipping lint. Install via: brew install swiftlint" >&2
fi

echo "Pre-commit checks passed." 
