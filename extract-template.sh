#!/usr/bin/env bash
# extract-template.sh <dest> — copy the template-owned files into a new directory.
#
# Copies exactly the files ./template-files.sh prints, from the working tree, keeping their
# paths and execute bits, and prints the count. <dest> must not exist or be empty.
# Exit 1: <dest> is not empty or a file is missing. 2: bad usage.

set -euo pipefail

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: extract-template.sh <dest>" >&2; exit 2; }
DEST=$1
ROOT=$(cd "$(dirname "$0")" && pwd)

if [ -e "$DEST" ]; then
  [ -d "$DEST" ] && [ -z "$(ls -A "$DEST")" ] || { echo "extract-template: $DEST exists and is not an empty directory" >&2; exit 1; }
fi
mkdir -p "$DEST"

n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$ROOT/$f" ] || { echo "extract-template: missing file: $f" >&2; exit 1; }
  mkdir -p "$DEST/$(dirname "$f")"
  cp -p "$ROOT/$f" "$DEST/$f"
  n=$((n + 1))
done <<LIST
$("$ROOT/template-files.sh")
LIST
echo "$n files copied to $DEST"
