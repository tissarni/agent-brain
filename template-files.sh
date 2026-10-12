#!/usr/bin/env sh
# List the template-owned files: the paths template.manifest covers.
#
#   ./template-files.sh            tracked files covered by the manifest
#   ./template-files.sh --staged   staged changes covered (deletions, both sides of renames)
#
# Paths are relative to the root, unquoted, one per line, sorted. Exit 2 on misuse.

dir=$(cd "$(dirname "$0")" && pwd) || exit 2
manifest="$dir/template.manifest"

mode=files
case "${1-}" in
  "") ;;
  --staged) mode=staged ;;
  *) echo "template-files: unknown argument: $1 (usage: template-files.sh [--staged])" >&2; exit 2 ;;
esac
[ -f "$manifest" ] || { echo "template-files: missing manifest: $manifest" >&2; exit 2; }

cd "$dir" || exit 2
# Entries become :(glob) pathspecs; an empty list would mean every file, so bail out first.
specs=$(sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$manifest" | sed 's/^/:(glob)/')
[ -n "$specs" ] || exit 0

set -f
OLDIFS=$IFS
IFS='
'
# shellcheck disable=SC2086
set -- $specs
IFS=$OLDIFS
if [ "$mode" = staged ]; then
  git -c core.quotePath=false diff --cached --name-only --no-renames -- "$@" | sort -u
else
  git -c core.quotePath=false ls-files -- "$@" | sort -u
fi
exit 0
