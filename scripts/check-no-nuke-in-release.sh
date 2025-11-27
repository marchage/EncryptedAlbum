#!/usr/bin/env bash
set -euo pipefail

# Fail if any non-test source files contain "nukeAllData(" outside a #if DEBUG region.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

files=$(git ls-files -- '*.swift' '*.m' '*.mm' '*.h' | grep -v -E '(^|/).*Tests?/|(^|/).*UITests?/')

bad_lines=()

for f in $files; do
  # scan for nukeAllData occurrences
  while IFS= read -r line; do
    if echo "$line" | grep -F -q "nukeAllData("; then
      lineno=$(echo "$line" | cut -d: -f2)
      is_non_debug=$(awk -v ln="$lineno" 'BEGIN{dbg=0}{ if ($0 ~ /^[[:space:]]*#[[:space:]]*if[[:space:]]+.*DEBUG/) dbg++; if ($0 ~ /^[[:space:]]*#[[:space:]]*endif/) { if (dbg>0) dbg-- } if (NR==ln) { print (dbg==0 ? "1" : "0") }}' "$f")
      if [ "$is_non_debug" = "1" ]; then
        bad_lines+=("$f:$line")
      fi
    fi
  done < <(grep -nH -F "nukeAllData(" "$f" || true)
done

if [ ${#bad_lines[@]} -gt 0 ]; then
  echo "ERROR: Found unconditional nukeAllData occurrences outside DEBUG blocks in non-test sources:" >&2
  for l in "${bad_lines[@]}"; do
    echo "$l" >&2
  done
  exit 1
fi

echo "No unconditional nukeAllData occurrences found in non-test sources."
