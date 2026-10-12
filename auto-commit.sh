#!/usr/bin/env sh
# Commit whatever changed in the vault, with a message derived from the paths touched.
# Wired to the Claude Code Stop hook so the vault versions itself without anyone thinking
# about it. Safe to run by hand at any time.
#
# Always exits 0 — a failed auto-commit must never break the session or a turn.

cd "$(dirname "$0")" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Keep the generated skills mirror fresh FIRST. Otherwise the pre-commit guard
# would reject this commit and changes would pile up unversioned and unnoticed —
# exactly the failure this whole setup exists to prevent.
[ -f ./sync-skills.sh ] && sh ./sync-skills.sh --apply >/dev/null 2>&1

# Refresh the docs site (HTML pages + index, outside the repo). Backgrounded and
# silenced: it must never slow the hook down or fail the turn.
[ -f ./build-docs-site.py ] && command -v python3 >/dev/null 2>&1 \
  && python3 ./build-docs-site.py </dev/null >/dev/null 2>&1 &

git add -A >/dev/null 2>&1
git diff --cached --quiet 2>&1 && exit 0   # nothing staged → nothing to do

FILES=$(git diff --cached --name-only | wc -l | tr -d ' ')

# In a brain that pulls from a template, note template-owned files in this commit. A warning only.
OWNED=""
if [ -f ./brain.env ] && [ -f ./template-files.sh ] && git remote get-url template >/dev/null 2>&1; then
  OWNED=$(sh ./template-files.sh --staged 2>/dev/null)
fi

# Areas touched, most specific label that is still short:
#   02-projects/<main>/...  -> <main>
#   01-daily/...            -> daily        05-weekly/... -> weekly
#   00-inbox/...            -> inbox        03-knowledge/... -> knowledge
#   .agents|.claude/...     -> skills       anything else -> config
# Cap at 4 names + "+N more". Never character-truncate a list of names —
# that invents names ("weekly" -> "week") and silently drops others.
ALL=$(git diff --cached --name-only | awk -F/ '
  $1=="02-projects" && $2!="" { print $2; next }
  $1=="01-daily"    { print "daily";     next }
  $1=="05-weekly"   { print "weekly";    next }
  $1=="00-inbox"    { print "inbox";     next }
  $1=="03-knowledge"{ print "knowledge"; next }
  $1==".agents" || $1==".claude" { print "skills"; next }
  { print "config" }
' | sort -u)
N=$(printf '%s\n' "$ALL" | grep -c .)
AREAS=$(printf '%s\n' "$ALL" | head -4 | paste -sd, - | sed 's/,/, /g')
[ "$N" -gt 4 ] && AREAS="$AREAS +$((N - 4)) more"

[ -z "$AREAS" ] && AREAS="vault"
if [ "$FILES" -eq 1 ]; then COUNT="1 file"; else COUNT="$FILES files"; fi

if git commit -q -m "vault: $AREAS ($COUNT)" >/dev/null 2>&1; then
  if [ -n "$OWNED" ]; then
    NOWNED=$(printf '%s\n' "$OWNED" | wc -l | tr -d ' ')
    FIRST=$(printf '%s\n' "$OWNED" | head -3 | paste -sd, - | sed 's/,/, /g')
    [ "$NOWNED" -gt 3 ] && FIRST="$FIRST +$((NOWNED - 3)) more"
    MSG="template-owned files changed ($NOWNED): $FIRST — make the change in the template too"
    MSG=$(printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    echo "{\"systemMessage\": \"$MSG\"}"
  else
    echo "{\"suppressOutput\": true}"
  fi
else
  # Commit refused (pre-commit guard, or a hook we could not satisfy). Say so
  # loudly rather than failing silently — silent non-committing is the one
  # outcome worse than a noisy one.
  echo "{\"systemMessage\": \"auto-commit failed — run ./auto-commit.sh by hand to see why\"}"
fi
exit 0
