#!/usr/bin/env sh
# Mirror the canonical skills (.agents/skills) into the Claude Code path (.claude/skills).
#
#   ./sync-skills.sh                  check only — reports drift, changes nothing
#   ./sync-skills.sh --apply          mirror canonical -> mirror (refuses if mirror diverged)
#   ./sync-skills.sh --force          mirror anyway, discarding mirror-only edits
#
# Why this exists: .agents/skills is the cross-client Agent Skills convention read by
# most tools; Claude Code only reads .claude/skills. One canonical copy, one generated
# mirror. Edit .agents/skills — never the mirror.
#
# The repo-side skills, the ones meant to run in a code repo rather than in this vault,
# belong to the handoff kit: its install.sh copies them into ~/.claude/skills/. No mode
# here writes to $HOME, since the vault's own Stop hook runs --apply after every session
# and would otherwise ship unmerged skill text to every repo session on the host.

set -eu
cd "$(dirname "$0")"
SRC=".agents/skills"
DST=".claude/skills"

[ -d "$SRC" ] || { echo "FATAL: canonical $SRC missing"; exit 1; }

MODE="check"
for a in "$@"; do
  case "$a" in
    --apply) MODE="apply" ;;
    --force) MODE="force" ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

if [ ! -d "$DST" ]; then
  echo "mirror $DST does not exist yet"
  DIFF="new"
else
  # --strip-trailing-cr: editors and scripts sometimes write CRLF. A line-ending
  # difference is not a content difference — flagging it would make the pre-commit
  # hook cry wolf.
  DIFF="$(diff -rq --strip-trailing-cr "$SRC" "$DST" 2>&1 || true)"
fi

if [ -z "${DIFF:-}" ]; then
  echo "in sync — $(find "$SRC" -name SKILL.md | wc -l | tr -d ' ') skills"
  exit 0
fi

echo "DRIFT between canonical and mirror:"
[ "$DIFF" = "new" ] || echo "$DIFF" | sed 's/^/  /'

# Anything present only in the mirror is either a skill DELETED from the canonical copy
# (safe — git still has it) or an edit made in the wrong place (unsafe — a plain --apply
# would destroy the only copy). Git tells the two apart: a deleted skill is still tracked
# in HEAD, a wrong-place edit never was. Refusing on both made every deletion look like a
# mistake and pushed you toward --force, which is the one flag that discards real work.
ONLY_DST="$(printf '%s' "${DIFF:-}" | grep "^Only in $DST" || true)"
UNTRACKED=""
if [ -n "$ONLY_DST" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # "Only in .claude/skills: daily" -> ".claude/skills/daily"
    p="$(printf '%s' "$line" | sed 's/^Only in \(.*\): \(.*\)$/\1\/\2/')"
    git ls-files --error-unmatch "$p" >/dev/null 2>&1 || UNTRACKED="$UNTRACKED  $p
"
  done <<EOF
$ONLY_DST
EOF
fi

if [ -n "$UNTRACKED" ] && [ "$MODE" != "force" ]; then
  echo
  echo "REFUSING: the mirror has files that are in no commit and not in $SRC:"
  printf '%s' "$UNTRACKED"
  echo "Someone edited $DST directly and it exists nowhere else."
  echo "Move those changes into $SRC first, or rerun with --force to discard them."
  exit 1
fi

if [ "$MODE" = "check" ]; then
  echo
  echo "check only — rerun with --apply to mirror"
  exit 1
fi

rm -rf "$DST"
mkdir -p "$(dirname "$DST")"
cp -r "$SRC" "$DST"
echo "mirrored $SRC -> $DST ($(find "$DST" -name SKILL.md | wc -l | tr -d ' ') skills)"
