#!/usr/bin/env bash
set -euo pipefail

# Search for accidental logging and dangerous debug-only helpers in non-test sources.
# Exits with non-zero if any are found so CI can fail early.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

# Files to inspect: tracked Swift/ObjC source files
files=$(git ls-files -- '*.swift' '*.m' '*.mm' '*.h' | grep -v -E '(^|/).*Tests?/|(^|/).*UITests?/|^ShareExtension/UITests')

bad_lines=()

for f in $files; do
  # Ignore the logging wrapper file itself
  if [[ "$f" =~ Logging.swift ]]; then
    continue
  fi

  # Search for common patterns
  if grep -nH -E "\bprint\s*\(|\bdebugPrint\s*\(|\bNSLog\s*\(|\bprintf\s*\(|\bnukeAllData\s*\(" "$f" >/dev/null 2>&1; then
    # Record the matching lines
    while IFS= read -r line; do
      # If this match is nukeAllData, ensure it's not inside a #if DEBUG block
      if echo "$line" | grep -F -q "nukeAllData("; then
        # Use awk to determine whether the matched line is inside a DEBUG-only region
        lineno=$(echo "$line" | cut -d: -f2)
        # awk: track #if DEBUG / #endif nesting and only print if nesting==0 (non-DEBUG)
        # Support both "#if DEBUG" and "# if DEBUG" variants
        is_non_debug=$(awk -v ln="$lineno" 'BEGIN{dbg=0}{ if ($0 ~ /^[[:space:]]*#[[:space:]]*if[[:space:]]+.*DEBUG/) dbg++; if ($0 ~ /^[[:space:]]*#[[:space:]]*endif/) { if (dbg>0) dbg-- } if (NR==ln) { print (dbg==0 ? "1" : "0") }}' "$f")
        if [ "$is_non_debug" = "1" ]; then
          bad_lines+=("$f:$line")
        fi
      else
        bad_lines+=("$f:$line")
      fi
    done < <(grep -nH -E "\bprint\s*\(|\bdebugPrint\s*\(|\bNSLog\s*\(|\bprintf\s*\(|\bnukeAllData\s*\(" "$f")
  fi
done

if [ ${#bad_lines[@]} -gt 0 ]; then
  echo "\nERROR: Found forbidden debug/logging/destructive patterns in non-test code. Replace them with AppLog or gate them to DEBUG.\n"
  for l in "${bad_lines[@]}"; do
    echo "$l"
  done
  echo
  echo "If any of the listed lines are intentional (very rare), add an explicit comment containing 'ALLOWED_PRINT' next to the line and update this script to whitelist it, but prefer AppLog or gating to DEBUG builds instead." >&2
  exit 1
fi

echo "No un-gated prints/debug helpers found in non-test sources.\n"
